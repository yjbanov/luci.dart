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

Future<void> main(List<String> args) async {
  final CommandRunner<bool> runner = CommandRunner<bool>(
    'luci',
    'Run LUCI targets.',
  )
    ..addCommand(TargetsCommand())
    ..addCommand(RunCommand());

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
}

/// Prints available targets to the standard output in JSON format.
class TargetsCommand extends Command<bool> with ArgUtils {
  TargetsCommand() {
    argParser.addFlag('pretty', help: 'Prints in human-readable format.');
  }

  @override
  String get name => 'targets';

  @override
  String get description => 'Prints the list of all available targets in JSON format.';

  @override
  FutureOr<bool> run() async {
    final List<Map<String, dynamic>> targetListJson = <Map<String, dynamic>>[];
    final Workspace workspace = await resolveWorkspace();
    final List<WorkspaceTarget> workspaceTargets = workspace.targetsInDependencyOrder;
    for (final WorkspaceTarget workspaceTarget in workspaceTargets) {
      targetListJson.add(workspaceTarget.toJson());
    }

    final JsonEncoder encoder = boolArg('pretty')
      ? const JsonEncoder.withIndent('  ')
      : const JsonEncoder();

    print(encoder.convert(<String, dynamic>{
      'targets': targetListJson,
    }));
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
      final Workspace workspace = await resolveWorkspace();
      final Iterable<WorkspaceTarget> availableTargets = workspace.targets.values;
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
      await runProcess(
        (await workspaceConfiguration).dartExecutable,
        <String>[buildFile.path, 'run', workspaceTarget.buildTarget.name],
        workingDirectory: buildFile.parent.path,
      );
    }
    return true;
  }
}
