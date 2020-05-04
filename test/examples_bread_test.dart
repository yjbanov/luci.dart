// Copyright 2013 The Flutter Authors. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

// @dart = 2.6
import 'dart:convert';

import 'package:test/test.dart';

import 'test_util.dart';

void main() {
  test('lists targets in dependency order', () async {
    final Map<String, dynamic> output = json.decode(await evalLuci(<String>['targets'], 'examples/bread'));
    expect(output, isNotEmpty);
    final List<Map<String, dynamic>> targets = output['targets'].cast<Map<String, dynamic>>();
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

  test('targets accepts --pretty', () async {
    await evalLuci(<String>['targets', '--pretty'], 'examples/bread');
  });

  test('can run targets', () async {
    await evalLuci(<String>['run', '//bakery:bread'], 'examples/bread');
    await evalLuci(<String>['run', '//farm:seeds'], 'examples/bread');
    await evalLuci(<String>['run', '//windmill:flour'], 'examples/bread');
  });
}
