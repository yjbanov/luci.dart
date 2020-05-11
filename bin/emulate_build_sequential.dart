// Copyright 2013 The Flutter Authors. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

/// Executes all targets in the workspace in dependency order sequentially.

// @dart = 2.6
import 'dart:async';
import 'dart:io' as io;

import 'package:luci/src/process.dart';
import 'package:luci/src/workspace.dart';

Future<void> main(List<String> args) async {
  await initializeWorkspaceConfiguration();
  for (WorkspaceTarget target in (await resolveBuildGraph()).targetsInDependencyOrder) {
    print('Running ${target.path}');
    final io.File buildFile = io.File(target.path.toBuildFilePath(workspaceConfiguration.rootDirectory));
    final io.Process targetProcess = await startProcess(
      workspaceConfiguration.dartExecutable,
      <String>[buildFile.path, 'run', target.buildTarget.name],
      workingDirectory: buildFile.parent.path,
    );
    if (await targetProcess.exitCode != 0) {
      io.stderr.writeln('Target ${target.path} failed');
      io.exit(1);
    }
  }
}
