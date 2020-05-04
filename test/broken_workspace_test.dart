// Copyright 2013 The Flutter Authors. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

// @dart = 2.6
import 'dart:io' as io;

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
}

Future<void> expectWorkspaceError(
    String testWorkspace, String expectedError) async {
  final io.ProcessResult result =
      await runLuci(<String>['targets'], testWorkspace);
  expect(result.stderr, expectedError);
}
