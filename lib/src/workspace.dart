// Copyright 2013 The Flutter Authors. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

// @dart = 2.6
import 'dart:async';
import 'dart:convert';
import 'dart:io' as io;

import 'package:meta/meta.dart';
import 'package:path/path.dart' as pathlib;
import 'package:yaml/yaml.dart';

import 'exceptions.dart';
import 'process.dart';

/// The name of the file that marks the root of a LUCI workspace.
///
/// LUCI targets are addressed relative to this file.
String kWorkspaceFileName = 'luci_workspace.yaml';

/// The file name used by LUCI build files that define build targets.
String kBuildFileName = 'build.luci.dart';

WorkspaceConfiguration _workspaceConfiguration;

FutureOr<WorkspaceConfiguration> get workspaceConfiguration async {
  if (_workspaceConfiguration == null) {
    _workspaceConfiguration = await WorkspaceConfiguration._fromCurrentDirectory();
  }
  return _workspaceConfiguration;
}

/// Workspace configuration.
@sealed
@immutable
class WorkspaceConfiguration {
  static Future<WorkspaceConfiguration> _fromCurrentDirectory() async {
    final io.Directory workspaceRoot = await findWorkspaceRoot();
    final io.File workspaceFile = io.File(pathlib.join(workspaceRoot.path, kWorkspaceFileName));
    final YamlMap workspaceYaml = loadYaml(await workspaceFile.readAsString());

    return WorkspaceConfiguration._(
      name: workspaceYaml['name'],
      dartSdkPath: await _resolveDartSdkPath(workspaceYaml['dart_sdk_path']),
      configurationFile: workspaceFile,
      rootDirectory: workspaceRoot,
    );
  }

  WorkspaceConfiguration._({
    @required this.name,
    @required this.dartSdkPath,
    @required this.configurationFile,
    @required this.rootDirectory,
  });

  /// The name of the workspace.
  ///
  /// Useful for debugging and dashboarding.
  final String name;

  /// The path to the Dart SDK.
  ///
  /// This is the directory that contains the `bin/` directory.
  final String dartSdkPath;

  final io.File configurationFile;

  final io.Directory rootDirectory;

  /// Path to the `dart` executable.
  String get dartExecutable => pathlib.join(dartSdkPath, 'bin', 'dart');
}

Future<String> _resolveDartSdkPath(String configValue) async {
  const String docs =
    'Please specify a correct dart_sdk_path. The value may be the path to a '
    'Dart SDK containing the bin/ directory, or the special value "_ENV_" '
    'that will try to locate it using the DART_SDK_PATH and PATH environment '
    'variables. See README.md for more information.';

  if (configValue == null) {
    throw ToolException(
      'dart_sdk_path is missing in ${await _findWorkspaceConfigFile()}.\n'
      '$docs'
    );
  }

  String dartSdkPathSource;
  io.Directory sdkPath = io.Directory(configValue);

  if (configValue == '_ENV_') {
    if (io.Platform.environment.containsKey('DART_SDK_PATH')) {
      dartSdkPathSource = 'DART_SDK_PATH environment variable';
      sdkPath = io.Directory(io.Platform.environment['DART_SDK_PATH']);
    } else {
      // TODO(yjbanov): implement for Windows.
      // TODO(yjbanov): implement look-up from the Flutter SDK.
      dartSdkPathSource = 'the PATH environment variable';
      final io.File dartBin = io.File(await evalProcess('which', <String>['dart']));
      sdkPath = dartBin.parent.parent;
    }
  } else {
    dartSdkPathSource = 'the ${await _findWorkspaceConfigFile()} file';
    sdkPath = io.Directory(configValue);
  }

  if (!await sdkPath.exists()) {
    throw ToolException(
      'dart_sdk_path "$configValue" specified in $dartSdkPathSource '
      'not found.\n'
      '$docs'
    );
  }

  return sdkPath.absolute.path;
}

io.Directory _workspaceRoot;

/// Finds the `luci_workspace.yaml` file.
FutureOr<io.File> _findWorkspaceConfigFile() async {
  return io.File(pathlib.join((await findWorkspaceRoot()).path, kWorkspaceFileName));
}

/// Find the root of the LUCI workspace starting from the current working directory.
///
/// A LUCI workspace root contains a file called "luci_workspace.yaml".
FutureOr<io.Directory> findWorkspaceRoot() async {
  if (_workspaceRoot != null) {
    return _workspaceRoot;
  }

  io.Directory directory = io.Directory.current;
  while(!await isWorkspaceRoot(directory)) {
    final io.Directory previousDirectory = directory;
    directory = directory.parent;

    if (directory.path == previousDirectory.path) {
      // Reached file system root.
      throw ToolException(
        'Failed to locate the LUCI workspace from ${io.Directory.current.absolute.path}.\n'
        'Make sure you run luci.dart from within a LUCI workspace. The workspace is identified '
        'by the presence of $kWorkspaceFileName file.',
      );
    }
  }
  return _workspaceRoot = directory.absolute;
}

/// Returns `true` if [directory] is a LUCI workspace root directory.
///
/// A LUCI workspace root contains a file called "luci_workspace.yaml".
Future<bool> isWorkspaceRoot(io.Directory directory) async {
  final io.File workspaceFile = await directory.list().firstWhere(
    (io.FileSystemEntity entity) {
      return entity is io.File && pathlib.basename(entity.path) == kWorkspaceFileName;
    },
    orElse: () => null) as io.File;
  return workspaceFile != null;
}

/// Returns `true` if [file] is a LUCI build file (see [kBuildFileName]).
bool isBuildFile(io.File file) => pathlib.basename(file.path) == kBuildFileName;

/// Lists all targets in the current workspace.
Future<Workspace> resolveWorkspace() async {
  return _WorkspaceResolver().resolve();
}

class Workspace {
  Workspace._({
    this.targets,
    this.targetsInDependencyOrder,
  });

  final Map<TargetPath, WorkspaceTarget> targets;
  final List<WorkspaceTarget> targetsInDependencyOrder;
}

class _WorkspaceResolver {
  /// Maps from workspace-relative target path to workspace target.
  final Map<TargetPath, WorkspaceTarget> workspaceTargetIndex = <TargetPath, WorkspaceTarget>{};

  /// Targets ordered according to their dependencies.
  final List<WorkspaceTarget> targetsInDependencyOrder = <WorkspaceTarget>[];

  /// Maps from target path to build target.
  final Map<TargetPath, BuildTarget> buildTargetIndex = <TargetPath, BuildTarget>{};

  Future<Workspace> resolve() async {
    final io.Directory workspaceRoot = await findWorkspaceRoot();

    final List<io.File> buildFiles = workspaceRoot
      .listSync(recursive: true)
      .whereType<io.File>()
      .where(isBuildFile)
      .toList();

    final List<MapEntry<io.File, String>> buildFilesWithNamespaces = <MapEntry<io.File, String>>[];
    for (io.File buildFile in buildFiles) {
      final String workspaceRelativePath = '${pathlib.relative(buildFile.absolute.parent.path, from: workspaceRoot.path)}';
      final String targetNamespace = workspaceRelativePath == '.'
        ? ''
        : pathlib.split(workspaceRelativePath).join('/');
      buildFilesWithNamespaces.add(MapEntry<io.File, String>(buildFile, targetNamespace));
    }

    // Sort files by namespace so they don't depend on the OS default file
    // listing order. Otherwise, we may report cycles in different order.
    buildFilesWithNamespaces.sort((a, b) {
      return a.value.compareTo(b.value);
    });

    for (MapEntry<io.File, String> entry in buildFilesWithNamespaces) {
      for (BuildTarget buildTarget in await listBuildTargets(workspaceRoot, entry.key)) {
        buildTargetIndex[TargetPath(entry.value, buildTarget.name)] = buildTarget;
      }
    }

    buildTargetIndex.forEach((TargetPath targetPath, BuildTarget buildTarget) {
      _resolveTarget(targetPath, buildTarget);
    });

    if (_cycles.isNotEmpty) {
      final StringBuffer error = StringBuffer('Dependency cycles detected:\n');
      for (List<TargetPath> cycle in _cycles) {
        error.writeln('  Cycle: ${cycle.join(' -> ')}');
      }
      throw ToolException(error.toString());
    }

    return Workspace._(
      targets: workspaceTargetIndex,
      targetsInDependencyOrder: targetsInDependencyOrder,
    );
  }

  List<TargetPath> _traversalStack = <TargetPath>[];
  List<List<TargetPath>> _cycles = <List<TargetPath>>[];

  WorkspaceTarget _resolveTarget(
    TargetPath targetPath,
    BuildTarget buildTarget,
  ) {
    if (workspaceTargetIndex.containsKey(targetPath)) {
      return workspaceTargetIndex[targetPath];
    }

    if (_traversalStack.contains(targetPath)) {
      _cycles.add(<TargetPath>[
        ..._traversalStack.sublist(_traversalStack.indexOf(targetPath)),
        targetPath,
      ]);
      return null;
    }

    _traversalStack.add(targetPath);

    final WorkspaceTarget target = WorkspaceTarget(
      path: targetPath,
      buildTarget: buildTarget,
      dependencies: buildTarget.dependencies
        .map((String dependencyPath) => _resolveDependency(dependencyPath, targetPath))
        // If there's a cycle the dependency resolves to null.
        // We don't stop the resolution process. Instead, we collect all cycles
        // then report them all.
        .where((WorkspaceTarget dependency) => dependency != null)
        .toList(),
    );
    workspaceTargetIndex[targetPath] = target;
    targetsInDependencyOrder.add(target);

    _traversalStack.removeLast();
    return target;
  }

  WorkspaceTarget _resolveDependency(String canonicalPath, TargetPath from) {
    final TargetPath dependencyPath = TargetPath.parse(canonicalPath, relativeTo: from);
    final BuildTarget buildTarget = buildTargetIndex[dependencyPath];

    if (buildTarget == null) {
      throw ToolException(
        'Build target $dependencyPath does not exist.\n'
        'Target $from specified it as its dependency.'
      );
    }

    return _resolveTarget(dependencyPath, buildTarget);
  }
}

/// Lists targest defined in one [buildFile].
Future<List<BuildTarget>> listBuildTargets(io.Directory workspaceRoot, io.File buildFile) async {
  final String buildFilePath = buildFile.absolute.path;
  final String buildTargetsOutput = await evalProcess(
    (await workspaceConfiguration).dartExecutable,
    <String>[buildFilePath, 'targets'],
    workingDirectory: buildFile.absolute.parent.path,
  );
  final Map<String, dynamic> buildTargetsJson = json.decode(buildTargetsOutput) as Map<String, dynamic>;
  return (buildTargetsJson['targets'] as List<dynamic>)
    .cast<Map<String, dynamic>>()
    .map<BuildTarget>(BuildTarget.fromJson)
    .toList();
}

/// Uniquely identifies a target within the workspace.
///
/// A target path is made of two parts: a namespace and a target name.
///
/// The namespace determines the directory within the workspace where the target
/// is defined. It also determines the build file that declares the target.
/// Namespace is unique for a given build file. However, it does not uniquely
/// identify a target.
///
/// The target name uniquely identifies a target within one build file. However,
/// it is not globally unique.
///
/// Together, the namespace and the target name uniquely identify a target
/// within the workspace.
@sealed
@immutable
class TargetPath {
  /// Parses a target path from a canonical string form.
  ///
  /// See also [canonicalPath].
  static TargetPath parse(String path, { TargetPath relativeTo }) {
    final bool isRelative = path.startsWith(':');

    if (isRelative && relativeTo == null) {
      throw ArgumentError(
        'Got relative path "$path", but "relativeTo" argument was null. '
        'This is a bug in luci.dart.',
      );
    }

    if (!path.startsWith('//') && !isRelative) {
      throw ToolException(
        'Invalid target path "$path".\n'
        'A target path can be absolute and begin with //, or it can be '
        'relative and begin with ":".');
    }

    if (isRelative) {
      // A relative path simply inherits its dependent's namespace.
      return TargetPath(relativeTo.namespace, path.split(':').last);
    }

    path = path.substring(2);
    final List<String> parts = path.split(':');

    if (parts.length != 2) {
      throw ToolException('Target path must have the format //path/to/package:target_name, but was $path');
    }

    return TargetPath(parts.first, parts.last);
  }

  TargetPath(this.namespace, this.targetName) {
    if (namespace.startsWith('//')) {
      throw ToolException('Target namespace must not include //, but was $namespace');
    }
  }

  /// Determines the directory within the workspace where the target is defined.
  ///
  /// Also determines the build file that declares the target. Namespace is
  /// unique for a given build file. However, it does not uniquely identify a
  /// target. To uniquely identify a target it needs to be combined with
  /// [targetName].
  final String namespace;

  /// Uniquely identifies a target within one build file.
  ///
  /// Target name alone does not uniquely identify a target. To uniquely
  /// identify a target it needs to be combined with [namespace].
  final String targetName;

  /// This target path in canonical string form.
  ///
  /// The canonical form is formatted as "//namespace:target_name", where "//"
  /// denotes the root of the workspace, the "namespace" is the path within
  /// the workspace (see [namespace]), and "target_name" is the name of the
  /// target within the build file (see [targetName]).
  ///
  /// The canonical form is used to uniquely identify targets within the
  /// workspace in configuration files, on the command-line, and in the
  /// serialized version of the build graph.
  String get canonicalPath => '//$namespace:$targetName';

  /// Converts this path to the build file path that declares the target.
  String toBuildFilePath(io.Directory workspaceRoot) {
    return pathlib.joinAll(<String>[
      workspaceRoot.path,
      // Windows uses "\", *nix uses "/", so we need to convert.
      ...namespace.split('/'),
      'build.luci.dart',
    ]);
  }

  @override
  int get hashCode => namespace.hashCode + 17 * targetName.hashCode;

  @override
  operator ==(Object other) {
    return other is TargetPath && other.namespace == namespace && other.targetName == targetName;
  }

  @override
  String toString() => canonicalPath;
}

/// Decorates a [BuildTarget] with workspace information.
@sealed
@immutable
class WorkspaceTarget {
  const WorkspaceTarget({
    @required this.path,
    @required this.buildTarget,
    @required this.dependencies,
  });

  /// The namespace of this target derived from the path to the `build.luci.dart`
  final TargetPath path;

  /// The description of the target defined in the `build.luci.dart`.
  final BuildTarget buildTarget;

  final List<WorkspaceTarget> dependencies;

  /// Serializes this target to JSON for digestion by the LUCI recipe.
  Map<String, dynamic> toJson() {
    return <String, dynamic>{
      'path': path.canonicalPath,
      'buildTarget': buildTarget.toJson(),
    };
  }
}

/// A build target defined in a `build.luci.dart` file.
///
/// This class only contains information local to the build file. See the
/// [WorkspaceTarget] class that contains workspace-level information about
/// a [BuildTarget].
@sealed
@immutable
class BuildTarget {
  /// Creates a concrete build target.
  const BuildTarget({
    @required this.name,
    @required this.agentProfiles,
    @required this.runner,
    @required this.environment,
    @required this.dependencies,
  });

  /// Deserializes JSON into an instance of this class.
  static BuildTarget fromJson(Map<String, dynamic> json) {
    return BuildTarget(
      name: json['name'] as String,
      agentProfiles: (json['agentProfiles'] as List<dynamic>).cast<String>(),
      runner: json['runner'] as String,
      dependencies: json.containsKey('dependencies')
        ? json['dependencies'].cast<String>()
        : const <String>[],
      environment: json.containsKey('environment')
        ? (json['environment'] as Map<String, dynamic>).cast<String, String>()
        : const <String, String>{},
    );
  }

  /// A unique name of the target.
  ///
  /// This name is used to identify this target and run it.
  final String name;

  /// Names of the agent profiles that this target can run on.
  ///
  /// Typically, this list contains one agent profile, but there can be
  /// use-cases for specifying multiple profiles, such as:
  ///
  /// - During a migration from an old profile to a new profile we may
  ///   temporarily specify both profiles, ramp up the new one, then remove
  ///   the old profile from this list, then finally sunset the old profile
  ///   agents.
  /// - When a target only cares about the host configuration and not the
  ///   devices. For example, you may need a Mac agent, but you don't care
  ///   if that agent has an Android device, iOS device, or no devices at all.
  ///   Then you can specify "mac-android", "mac-ios", and "mac".
  final List<String> agentProfiles;

  /// The name of the class that runs this target.
  ///
  /// This value is only useful for debugging as there is no way to get an
  /// actual runner instance from the string.
  final String runner;

  /// Targets within the workspace that this target depends on.
  ///
  /// Dependencies are specified using workspace-relative paths.
  final List<String> dependencies;

  /// Additional environment variables used when running this target.
  final Map<String, String> environment;

  /// Serializes this target to JSON for digestion by the LUCI recipe.
  Map<String, dynamic> toJson() {
    return <String, dynamic>{
      'name': name,
      'agentProfiles': agentProfiles,
      'runner': runner,
      if (environment.isNotEmpty)
        'environment' : environment,
      if (dependencies.isNotEmpty)
        'dependencies': dependencies,
    };
  }
}
