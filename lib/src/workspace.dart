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
    );
  }

  WorkspaceConfiguration._({
    @required this.name,
    @required this.dartSdkPath,
  });

  /// The name of the workspace.
  ///
  /// Useful for debugging and dashboarding.
  final String name;

  /// The path to the Dart SDK.
  ///
  /// This is the directory that contains the `bin/` directory.
  final String dartSdkPath;

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
      'dart_sdk_path is missing in ${await findWorkspaceConfigFile()}.\n'
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
    dartSdkPathSource = 'the ${await findWorkspaceConfigFile()} file';
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
FutureOr<io.File> findWorkspaceConfigFile() async {
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
Future<List<WorkspaceTarget>> listWorkspaceTargets() async {
  final io.Directory workspaceRoot = await findWorkspaceRoot();

  final List<io.File> buildFiles = workspaceRoot
    .listSync(recursive: true)
    .whereType<io.File>()
    .where(isBuildFile)
    .toList();

  final List<WorkspaceTarget> workspaceTargets = <WorkspaceTarget>[];
  for (io.File buildFile in buildFiles) {
    workspaceTargets.addAll(await listWorkspaceTargetForBuildFile(workspaceRoot, buildFile));
  }
  return workspaceTargets;
}

/// Lists targest defined in one [buildFile].
Future<List<WorkspaceTarget>> listWorkspaceTargetForBuildFile(io.Directory workspaceRoot, io.File buildFile) async {
  final String buildFilePath = buildFile.absolute.path;
  final String buildTargetsOutput = await evalProcess(
    (await workspaceConfiguration).dartExecutable,
    <String>[buildFilePath, 'targets'],
    workingDirectory: buildFile.absolute.parent.path,
  );
  final Map<String, dynamic> buildTargetsJson = json.decode(buildTargetsOutput) as Map<String, dynamic>;
  final List<WorkspaceTarget> targets = (buildTargetsJson['targets'] as List<dynamic>)
    .cast<Map<String, dynamic>>()
    .map<BuildTarget>(BuildTarget.fromJson)
    .map<WorkspaceTarget>((BuildTarget buildTarget) {
      return WorkspaceTarget(
        namespace: '//${pathlib.relative(buildFile.absolute.parent.path, from: workspaceRoot.path)}',
        buildTarget: buildTarget,
      );
    })
    .toList();
  return targets;
}

@sealed
@immutable
class TargetPath {
  static TargetPath parse(String path) {
    if (!path.startsWith('//')) {
      // TODO(yjbanov): support relative paths too
      throw ToolException('Target path must begin with //, but was $path');
    }

    path = path.substring(2);
    final List<String> parts = path.split(':');

    if (parts.length != 2) {
      throw ToolException('Target path must have the format //path/to/package:target_name, but was $path');
    }

    return TargetPath._(parts.first, parts.last);
  }

  const TargetPath._(this.workspaceRelativePath, this.targetName);

  final String workspaceRelativePath;
  final String targetName;

  String get canonicalPath => '//$workspaceRelativePath:$targetName';

  String toBuildFilePath(io.Directory workspaceRoot) {
    return pathlib.joinAll(<String>[
      workspaceRoot.path,
      // Windows uses "\", *nix uses "/", so we need to convert.
      ...workspaceRelativePath.split('/'),
      'build.luci.dart',
    ]);
  }

  @override
  String toString() => canonicalPath;
}

/// Decorates a [BuildTarget] with workspace information.
@sealed
@immutable
class WorkspaceTarget {
  const WorkspaceTarget({
    @required this.namespace,
    @required this.buildTarget,
  });

  /// The namespace of this target derived from the path to the `build.luci.dart`
  final String namespace;

  /// The path to the target relative to the workspace.
  ///
  /// This path can be used from anywhere within the workspace to refer to this
  /// target.
  String get canonicalPath => '$namespace:${buildTarget.name}';

  /// The description of the target defined in the `build.luci.dart`.
  final BuildTarget buildTarget;

  /// Serializes this target to JSON for digestion by the LUCI recipe.
  Map<String, dynamic> toJson() {
    return <String, dynamic>{
      'path': canonicalPath,
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
  });

  /// Deserializes JSON into an instance of this class.
  static BuildTarget fromJson(Map<String, dynamic> json) {
    return BuildTarget(
      name: json['name'] as String,
      agentProfiles: (json['agentProfiles'] as List<dynamic>).cast<String>(),
      runner: json['runner'] as String,
      environment: json.containsKey('environment')
        ? (json['environment'] as Map<String, dynamic>).cast<String, String>()
        : null,
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

  /// Additional environment variables used when running this target.
  final Map<String, String> environment;

  /// Serializes this target to JSON for digestion by the LUCI recipe.
  Map<String, dynamic> toJson() {
    return <String, dynamic>{
      'name': name,
      'agentProfiles': agentProfiles,
      'runner': runner,
      if (environment != null)
        'environment' : environment,
    };
  }
}
