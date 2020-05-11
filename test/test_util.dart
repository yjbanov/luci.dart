// Copyright 2013 The Flutter Authors. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

// @dart = 2.6
import 'dart:io' as io;

import 'package:path/path.dart' as pathlib;

import 'package:luci/src/workspace.dart';
import 'package:luci/src/process.dart';

/// Runs the `luci.dart` tool and returns its standard output as a string.
///
/// This utility is useful when the sub-process is expected to never fail.
Future<String> evalLuci(List<String> args, String workingDirectory) async {
  await initializeWorkspaceConfiguration();
  return await evalProcess(
    workspaceConfiguration.dartExecutable,
    <String>[
      pathlib.join(workspaceConfiguration.rootDirectory.path, 'bin', 'luci.dart'),
      ...args,
    ],
    workingDirectory: pathlib.join(workspaceConfiguration.rootDirectory.path, workingDirectory),
  );
}

/// Runs the `luci.dart` tool and returns the result.
///
/// This utility is useful when the sub-process may succeed or fail.
Future<io.ProcessResult> runLuci(List<String> args, String workingDirectory) async {
  await initializeWorkspaceConfiguration();
  return io.Process.run(
    workspaceConfiguration.dartExecutable,
    <String>[
      pathlib.join(workspaceConfiguration.rootDirectory.path, 'bin', 'luci.dart'),
      ...args,
    ],
    workingDirectory: pathlib.join(workspaceConfiguration.rootDirectory.path, workingDirectory),
  );
}
