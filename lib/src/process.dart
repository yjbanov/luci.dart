// Copyright 2013 The Flutter Authors. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

// @dart = 2.6
import 'dart:io' as io;

import 'package:meta/meta.dart';

import 'cleanup.dart';

/// Starts a new process by executing a command with [executable] and [arguments].
Future<io.Process> startProcess(
  String executable,
  List<String> arguments, {
  String workingDirectory,
  Map<String, String> environment,
  bool mustSucceed = false,
}) async {
  environment ??= const <String, String>{};
  final io.Process process = await io.Process.start(
    executable,
    arguments,
    workingDirectory: workingDirectory,
    // Running the process in a system shell for Windows. Otherwise
    // the process is not able to get Dart from path.
    runInShell: io.Platform.isWindows,
    mode: io.ProcessStartMode.inheritStdio,
    environment: environment,
  );

  bool processExited = false;

  process.exitCode.then((int exitCode) {
    processExited = true;
  });

  // Make sure to clean up child processes.
  scheduleCleanup(() async {
    if (!processExited) {
      process.kill();
    }
  });

  return process;
}

/// Runs [executable] and returns its standard output as a string.
///
/// If the process fails, throws a [ProcessException].
Future<String> evalProcess(
  String executable,
  List<String> arguments, {
  String workingDirectory,
  Map<String, String> environment,
}) async {
  environment ??= const <String, String>{};
  final io.ProcessResult result = await io.Process.run(
    executable,
    arguments,
    workingDirectory: workingDirectory,
    environment: environment,
  );
  if (result.exitCode != 0) {
    throw ProcessException(
      description: result.stderr as String,
      executable: executable,
      arguments: arguments,
      workingDirectory: workingDirectory,
      exitCode: result.exitCode,
    );
  }
  return result.stdout as String;
}

/// Thrown by process utility functions, such as [evalProcess], when a process
/// exits with a non-zero exit code.
@immutable
class ProcessException implements Exception {
  /// Instantiates a process exception.
  const ProcessException({
    @required this.description,
    @required this.executable,
    @required this.arguments,
    @required this.workingDirectory,
    @required this.exitCode,
  });

  /// Describes what went wrong.
  final String description;

  /// The executable used to start the process that failed.
  final String executable;

  /// Arguments passed to the [executable].
  final List<String> arguments;

  /// The working directory of the process.
  final String workingDirectory;

  /// The exit code that the process exited with, if it exited.
  final int exitCode;

  @override
  String toString() {
    final StringBuffer message = StringBuffer();
    message
      ..writeln(description)
      ..writeln('Command: $executable ${arguments.join(' ')}')
      ..writeln(
          'Working directory: ${workingDirectory ?? io.Directory.current.path}')
      ..writeln('Exit code: $exitCode');
    return '$message';
  }
}
