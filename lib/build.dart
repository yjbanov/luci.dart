// Copyright 2013 The Flutter Authors. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

/// Provides the core concepts of the build framework, such as [Target] and
/// [TargetRunner].

// @dart = 2.6
import 'dart:async';
import 'dart:convert';
import 'dart:io' as io;

import 'package:args/command_runner.dart';
import 'package:meta/meta.dart';

import 'src/cleanup.dart';
import 'src/exceptions.dart';

/// Standard Linux LUCI build agent.
///
/// Use this as the [Target.agentProfiles] value.
const List<String> kLinuxAgent = <String>['linux'];

/// Standard Mac LUCI build agent.
///
/// Use this as the [Target.agentProfiles] value.
const List<String> kMacAgent = <String>['mac'];

/// Standard Windows LUCI build agent.
///
/// Use this as the [Target.agentProfiles] value.
const List<String> kWindowsAgent = <String>['windows'];

/// A callback passed to [build].
typedef BuildCallback = FutureOr<void> Function();

/// Declares a list of targets under the a shared namespace.
///
/// Targets are delcared by calling [target] inside the [callback].
///
/// Asynchronous work is permissed inside the [callback]. However, it is
/// expected that the execution time of the callback is very fast (single-digit
/// milliseconds) to ensure fast CI builds.
void build(List<String> args, BuildCallback callback) {
  final _Builder builder = _Builder();

  // Use a zone to implicitly pass the _Builder to the `target`
  // function. This is so build definition code is never exposed
  // to the _Builder class.
  final Zone buildZone = Zone.current.fork(
    specification: const ZoneSpecification(),
    zoneValues: <String, dynamic>{
      'luci.builder': builder,
    },
  );

  buildZone.run(() async {
    await callback();

    final CommandRunner<bool> runner = CommandRunner<bool>(
      'luci',
      'Run LUCI targets.',
    )
      ..addCommand(_TargetsCommand(builder))
      ..addCommand(_RunCommand(builder));

    if (args.isEmpty) {
      // Invoked with no arguments. Print usage.
      runner.printUsage();
      io.exit(64); // Exit code 64 indicates a usage error.
    }

    try {
      await runner.run(args);
    } on ToolException catch(error) {
      io.stderr.writeln(error.message);
      io.exitCode = 1;
    } finally {
      await cleanup();
    }

    // Sometimes the Dart VM refuses to quit if there are open "ports" (could be
    // network, open files, processes, isolates, etc). Calling `exit` explicitly
    // is the surest way to quit the process.
    io.exit(io.exitCode);
  });
}

/// Declares a target.
///
/// This function must be called within the `callback` passed to the [build]
/// function.
///
/// Target [name] must be unique within one build.
///
/// [agentProfiles] lists build profiles that this target can execute on. Use
/// this to request specific resources. There may be many different kinds of
/// build agents, but for convenience standard agent profiles can be specified
/// using the constants [kLinuxAgent], [kWindowsAgent], [kMacAgent].
///
/// When running the target declared by calling this function [runner] is used.
///
/// [environment] contains additional environment variables required by the
/// target runner.
void target({
  @required String name,
  @required List<String> agentProfiles,
  @required TargetRunner runner,
  Map<String, String> environment,
}) {
  final _Builder builder = Zone.current['luci.builder'] as _Builder;

  if (builder == null) {
    throw ToolException(
      'The `target` function was called outside the `build` callback.\n'
      'To define a target call the function inside a callback passed to `build`, e.g.:\n'
      '\n'
      'build(() {\n'
      '  target(...);'
      '});'
    );
  }

  builder.addTarget(Target._(
    name: name,
    agentProfiles: agentProfiles,
    runner: runner,
    environment: environment,
  ));
}

/// Encapsulates a list of targets.
class _Builder {
  final List<Target> _targets = <Target>[];

  List<Target> get targets => _targets;

  void addTarget(Target target) {
    if (targets.any((Target existingTarget) => existingTarget.name == target.name)) {
      throw ToolException(
        'A target named "${target.name}" is already defined.\n'
        'Target names must be unique within one build.luci.dart file.',
      );
    }
    _targets.add(target);
  }
}

/// Prints available targets to the standard output in JSON format.
class _TargetsCommand extends Command<bool> {
  _TargetsCommand(this.builder) {
    argParser.addFlag('pretty', help: 'Prints in human-readable format.');
  }

  final _Builder builder;

  @override
  String get name => 'targets';

  @override
  String get description => 'Prints the list of all available targets in JSON format.';

  @override
  FutureOr<bool> run() async {
    final List<Map<String, dynamic>> targetListJson = <Map<String, dynamic>>[];
    for (final Target target in builder.targets) {
      targetListJson.add(target.toJson());
    }

    final JsonEncoder encoder = argResults['pretty'] as bool
      ? const JsonEncoder.withIndent('  ')
      : const JsonEncoder();

    print(encoder.convert(<String, dynamic>{
      'targets': targetListJson,
    }));
    return true;
  }
}

/// Runs LUCI targets.
class _RunCommand extends Command<bool> {
  _RunCommand(this.builder);

  final _Builder builder;

  @override
  String get name => 'run';

  @override
  String get description => 'Runs targets.';

  List<String> get targetNames => argResults.rest;

  @override
  FutureOr<bool> run() async {
    for (final String targetName in targetNames) {
      final Target target = builder.targets.singleWhere(
        (Target t) => t.name == targetName,
        orElse: () {
          throw ToolException('Target $targetName not found.');
        },
      );
      await target.runner.run(target);
    }
    return true;
  }
}

final RegExp _kTargetNameRegex = RegExp(r'[_\-a-zA-Z0-9]+');

/// A build or test target that can be run using `luci.dart run`.
@immutable
@sealed
class Target {
  /// Creates a concrete build target.
  Target._({
    @required this.name,
    @required this.agentProfiles,
    @required this.runner,
    this.environment,
  }) {
    if (_kTargetNameRegex.matchAsPrefix(name) == null) {
      throw ToolException(
        'Invalid target name "$name".\n'
        'Target name may only contain upper or lower letters, numbers, underscores, and dashes.',
      );
    }
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

  /// Runs this target.
  final TargetRunner runner;

  /// Additional environment variables used when running this target.
  final Map<String, String> environment;

  /// Serializes this target to JSON for digestion by the LUCI recipe.
  Map<String, dynamic> toJson() {
    return <String, dynamic>{
      'name': name,
      'agentProfiles': agentProfiles,
      'runner': runner.runtimeType.toString(),
      if (environment != null)
        'environment' : environment,
    };
  }
}

/// Runs LUCI targets.
///
/// Implement this class to provide concrete logic behind targets.
abstract class TargetRunner {
  // Prevents this class from being extended.
  factory TargetRunner._() => throw 'This class must be implemented, not extended.';

  /// Runs a single target given the target's description.
  Future<void> run(Target target);
}
