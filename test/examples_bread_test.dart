// Copyright 2013 The Flutter Authors. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

// @dart = 2.6
import 'dart:convert';
import 'dart:io' as io;

import 'package:test/test.dart';

import 'test_util.dart';

void main() {
  test('lists targets in dependency order', () async {
    final List<dynamic> targetsJson = json.decode(await evalLuci(<String>['targets'], 'examples/bread'));
    final List<Map<String, dynamic>> targets = targetsJson.cast<Map<String, dynamic>>();
    final List<String> targetPaths = targets.map<String>((target) => target['path']).toList();
    expect(
      targetPaths,
      containsAll(<String>[
        '//bakery:bread',
        '//farm:water',
        '//farm:seeds',
        '//farm:compost',
        '//farm:wheat',
        '//windmill:flour',
      ]),
    );

    // Make sure the order follows dependencies
    final Map<String, List<String>> dependencyMap = <String, List<String>>{
      '//bakery:bread': ['//farm:water', '//windmill:flour'],
      '//windmill:flour': ['//farm:wheat'],
      '//farm:wheat': ['//farm:water', '//farm:seeds', '//farm:compost'],
    };
    dependencyMap.forEach((String target, List<String> dependencies) {
      for (String dependency in dependencies) {
        expect(
          targetPaths.indexOf(target),
          greaterThan(targetPaths.indexOf(dependency)),
          reason: '$target should execute after $dependency'
        );
      }
    });
  });

  test('can run targets', () async {
    await evalLuci(<String>['run', '//bakery:bread'], 'examples/bread');
    await evalLuci(<String>['run', '//farm:seeds'], 'examples/bread');
    await evalLuci(<String>['run', '//windmill:flour'], 'examples/bread');
  });

  test('can validate a workspace', () async {
    expect(
      await evalLuci(<String>['snapshot', '--validate'], 'examples/bread'),
      'The build graph snapshot for this workspace is up-to-date.\n',
    );
  });

  test('missing snapshot command arguments', () async {
    final io.ProcessResult result =
      await runLuci(<String>['snapshot'], 'examples/bread');
    expect(result.exitCode, 64);
    expect(
      result.stderr,
      'Don\'t know what to do. Neither --validate nor --update flags were set.\n\n'
      'Please specify --validate or --update. Run `luci snapshot help` for more details.\n\n',
    );
  });

  test('snapshot --update --validate', () async {
    final io.ProcessResult result =
      await runLuci(<String>['snapshot', '--update', '--validate'], 'examples/bread');
    expect(result.exitCode, 64);
    expect(
      result.stderr,
      '--validate and --update flags were both set.\n\n'
      'Specify --validate or --update, but not both. Run `luci snapshot help` for more details.\n\n',
    );
  });
}
