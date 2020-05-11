// Copyright 2013 The Flutter Authors. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

// @dart = 2.6
import 'package:luci/build.dart';

import 'runners.dart';

void main(List<String> args) => build(args, () {
  _createTargets('linux');
  _createTargets('windows');
  _createTargets('mac');
});

void _createTargets(String os) {
  target(
    name: 'host_debug_unopt_$os',
    agentProfiles: <String>[os],
    runner: hostDebugUnoptRunner,
  );

  target(
    name: 'license_check_$os',
    agentProfiles: <String>[os],
    runner: licenseCheckRunner,
    dependencies: [
      ':host_debug_unopt_$os',
    ]
  );

  target(
    name: 'canvaskit_$os',
    agentProfiles: <String>[os],
    runner: canvasKitRunner,
    dependencies: [
      ':license_check_$os',
    ],
  );

  target(
    name: 'compile_html_tests_$os',
    agentProfiles: <String>[os],
    runner: testCompilerRunner,
    dependencies: [
      ':canvaskit_$os',
    ]
  );

  target(
    name: 'compile_canvaskit_tests_$os',
    agentProfiles: <String>[os],
    runner: testCompilerRunner,
    dependencies: [
      ':compile_html_tests_$os',
    ]
  );

  String lastShard = ':compile_canvaskit_tests_$os';
  for (String testType in ['html', 'canvaskit']) {
    for (int shard in [1, 2, 3, 4, 5, 6, 7, 8]) {
      lastShard = createTestShard(testType, os, shard, lastShard);
    }
  }
}

String createTestShard(String testType, String os, int shard, String dependency) {
  final String shardName = 'web_tests_${testType}_${shard}_$os';
  target(
    name: shardName,
    agentProfiles: <String>[os],
    runner: testShardRunner,
    dependencies: [dependency],
  );
  return ':$shardName';
}
