// Copyright 2013 The Flutter Authors. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

/// The command-line tool used to inspect and run LUCI build targets.

// @dart = 2.6
import 'dart:async';
import 'dart:convert';
import 'dart:io' as io;

import 'package:args/command_runner.dart';

import 'package:luci/src/cleanup.dart';
import 'package:luci/src/exceptions.dart';
import 'package:luci/src/process.dart';
import 'package:luci/src/workspace.dart';
import 'package:luci/src/args.dart';

/// The standard JSON encoder used to encode the output of `luci.dart` sub-commands.
const _kJsonEncoder = const JsonEncoder.withIndent('  ');

Future<void> main(List<String> args) async {
  await initializeWorkspaceConfiguration();

  final CommandRunner<bool> runner = CommandRunner<bool>(
    'luci',
    'Run LUCI targets.',
  )
    ..addCommand(TargetsCommand())
    ..addCommand(RunCommand())
    ..addCommand(SnapshotCommand());

  if (args.isEmpty) {
    // Invoked with no arguments. Print usage.
    runner.printUsage();
    io.exit(64); // Exit code 64 indicates a usage error.
  }

  try {
    await runner.run(args);
  } on ToolException catch (error) {
    io.stderr.writeln(error.message);
    io.exitCode = 1;
  } on UsageException catch (error) {
    io.stderr.writeln('$error\n');
    runner.printUsage();
    io.exitCode = 64; // Exit code 64 indicates a usage error.
  } finally {
    await cleanup();
  }

  // Sometimes the Dart VM refuses to quit if there are open "ports" (could be
  // network, open files, processes, isolates, etc). Calling `exit` explicitly
  // is the surest way to quit the process.
  io.exit(io.exitCode);
}

/// Prints available targets to the standard output in JSON format.
class TargetsCommand extends Command<bool> with ArgUtils {
  @override
  String get name => 'targets';

  @override
  String get description => 'Prints the list of all available targets in JSON format.';

  @override
  FutureOr<bool> run() async {
    final BuildGraph buildGraph = await resolveBuildGraph();
    print(_kJsonEncoder.convert(buildGraph.toJson()['targets']));
    return true;
  }
}

/// Serializes the build graph to `luci.snapshot.json` in JSON format.
class SnapshotCommand extends Command<bool> with ArgUtils {
  SnapshotCommand() {
    argParser.addFlag(
      'validate',
      help: 'Checks that the `luci.snapshot.json` is consistent with `build.luci.dart` files.',
    );
    argParser.addFlag(
      'update',
      help: 'Writes a new `luci.snapshot.json` file from `build.luci.dart` files.',
    );
  }

  @override
  String get name => 'snapshot';

  /// Whether this command was instructed to validate an existing snapshot file.
  bool get isValidate => boolArg('validate');

  /// Whether this command was instructed to write a new snapshot file.
  bool get isUpdate => boolArg('update');

  @override
  String get description =>
    'Serializes the build graph to `luci.snapshot.json` in JSON format. Tools '
    'can use the snapshot for further analysis and execution, without a '
    'dependency on luci.dart. Exactly one of --validate and --update must be '
    'specified.';

  @override
  FutureOr<bool> run() async {
    const String hint = 'Run `luci snapshot help` for more details.';

    if (isValidate && isUpdate) {
      throw UsageException(
        '--validate and --update flags were both set.',
        'Specify --validate or --update, but not both. $hint');
    }

    if (!isValidate && !isUpdate) {
      throw UsageException(
        'Don\'t know what to do. Neither --validate nor --update flags were set.',
        'Please specify --validate or --update. $hint');
    }

    final BuildGraph buildGraph = await resolveBuildGraph();
    final String serializedBuildGraph = _kJsonEncoder.convert(buildGraph.toJson());
    final io.File snapshotFile = workspaceConfiguration.buildGraphSnapshotFile;

    if (isUpdate) {
      await snapshotFile.writeAsString(serializedBuildGraph);
    } else if (isValidate) {
      const String validationFailedMessage = 'Build graph snapshot validation failed.';
      if (!snapshotFile.existsSync()) {
        throw ToolException(
          '$validationFailedMessage\n'
          'Snapshot file `luci.snapshot.json` not found.',
        );
      }

      final String existingContents = await snapshotFile.readAsString();
      if (existingContents != serializedBuildGraph) {
        throw ToolException(
          '$validationFailedMessage\n'
          'The contents of the existing build graph snapshot file are '
          'different from the snapshot generated from `build.luci.dart` '
          'files. Use `luci snapshot --update` to update the snapshot file.',
        );
      }
    } else {
      throw StateError(
        'This code should not be reachable. This is a bug in the `luci.dart` tool.',
      );
    }

    print('The build graph snapshot for this workspace is up-to-date.');
    return true;
  }
}

/// Runs LUCI targets.
class RunCommand extends Command<bool> with ArgUtils {
  @override
  String get name => 'run';

  @override
  String get description => 'Runs targets.';

  List<String> get targetPaths => argResults.rest;

  @override
  FutureOr<bool> run() async {
    final io.Directory workspaceRoot = await findWorkspaceRoot();

    for (final String rawPath in targetPaths) {
      final TargetPath targetPath = TargetPath.parse(rawPath);
      final io.File buildFile = io.File(targetPath.toBuildFilePath(workspaceRoot));

      if (!buildFile.existsSync()) {
        throw ToolException(
          '${buildFile.path} not found.\n'
          'Expected to find it based on the specified target path $rawPath.',
        );
      }

      // TODO(yjbanov): execute dependencies too.
      final BuildGraph buildGraph = await resolveBuildGraph();
      final Iterable<WorkspaceTarget> availableTargets = buildGraph.targets.values;
      final WorkspaceTarget workspaceTarget = availableTargets.firstWhere(
        (WorkspaceTarget target) => target.path == targetPath,
        orElse: () {
          throw ToolException(
            'Target $rawPath not found.\n'
            'Make sure that ${buildFile.path} defines this target. Available targets in that file are:\n'
            '${availableTargets.map((WorkspaceTarget target) => target.path.canonicalPath).join('\n')}'
          );
        },
      );

      print('Running $targetPath');
      final io.Process targetProcess = await startProcess(
        workspaceConfiguration.dartExecutable,
        <String>[buildFile.path, 'run', workspaceTarget.buildTarget.name],
        workingDirectory: buildFile.parent.path,
      );

      final int exitCode = await targetProcess.exitCode;

      if (exitCode != 0) {
        io.stderr.writeln('Target $targetPath failed');
      }
    }
    return true;
  }
}
