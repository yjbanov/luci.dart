// Copyright 2013 The Flutter Authors. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

// @dart = 2.6
import 'dart:io' as io;

import 'package:path/path.dart' as pathlib;
import 'package:test/test.dart';

import 'test_util.dart';

void main() {
  test('target that depends on itself', () async {
    await expectWorkspaceError(
      'examples/broken/cycles_self',
      'Dependency cycles detected:\n'
          '  Cycle: //:foo -> //:foo\n'
          '\n',
    );
  });

  test('targets that depend on each other within the same build file',
      () async {
    await expectWorkspaceError(
      'examples/broken/cycles_within_build_file',
      'Dependency cycles detected:\n'
          '  Cycle: //:foo -> //:bar -> //:foo\n'
          '\n',
    );
  });

  test('targets that depend on each other across build files', () async {
    await expectWorkspaceError(
      'examples/broken/cycles_across_build_files',
      'Dependency cycles detected:\n'
          '  Cycle: //bar:bar -> //foo:foo -> //bar:bar\n'
          '\n',
    );
  });

  test('targets that have transitive cycles', () async {
    await expectWorkspaceError(
      'examples/broken/cycles_transitive',
      'Dependency cycles detected:\n'
          '  Cycle: //bar:bar -> //baz:baz -> //foo:foo -> //bar:bar\n'
          '\n',
    );
  });

  test('targets that have multiple cycles', () async {
    await expectWorkspaceError(
      'examples/broken/cycles_multiple',
      'Dependency cycles detected:\n'
          '  Cycle: //bar:bar -> //foo:foo -> //bar:bar\n'
          '  Cycle: //foo:foo -> //foo:baz -> //foo:foo\n'
          '\n',
    );
  });

  test('snapshot missing', () async {
    final io.ProcessResult result =
      await runLuci(<String>['snapshot', '--validate'], 'examples/broken/snapshot_missing');
    expect(result.exitCode, 1);
    expect(
      result.stderr,
      'Build graph snapshot validation failed.\n'
      'Snapshot file `luci.snapshot.json` not found.\n',
    );
  });

  test('snapshot out of date', () async {
    final io.ProcessResult result =
      await runLuci(<String>['snapshot', '--validate'], 'examples/broken/snapshot_out_of_date');
    expect(result.exitCode, 1);
    expect(
      result.stderr,
      'Build graph snapshot validation failed.\n'
      'The contents of the existing build graph snapshot file are '
      'different from the snapshot generated from `build.luci.dart` '
      'files. Use `luci snapshot --update` to update the snapshot file.\n',
    );
  });

  test('target does not exist', () async {
    final io.ProcessResult result =
      await runLuci(<String>['targets'], 'examples/broken/target_does_not_exist');
    expect(result.exitCode, 1);
    final String pathToBuildFile = pathlib.join(io.Directory.current.path, 'examples/broken/target_does_not_exist/build.luci.dart');
    expect(
      result.stderr,
      'Build target //:bar does not exist.\n'
      'Target //:foo (defined in file $pathToBuildFile) specified it as its dependency.\n'
      'Possible fixes for this error:\n'
      '* Remove this dependency from //:foo\n'
      '* Add the missing target "bar" in $pathToBuildFile\n',
    );
  });
}

Future<void> expectWorkspaceError(
    String testWorkspace, String expectedError, { int expectedExitCode = 1 }) async {
  final io.ProcessResult result =
      await runLuci(<String>['targets'], testWorkspace);
  expect(result.exitCode, expectedExitCode);
  expect(result.stderr, expectedError);
}
