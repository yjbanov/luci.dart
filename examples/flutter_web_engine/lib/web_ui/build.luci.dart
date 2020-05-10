// Copyright 2013 The Flutter Authors. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

// @dart = 2.6
import 'package:luci/build.dart';

import '../../runners.dart';

void main(List<String> args) => build(args, () {
  target(
    name: 'license_check',
    agentProfiles: kLinuxAgent,
    runner: licenseCheckRunner,
    dependencies: [
      '//:host_debug_unopt_linux',
    ]
  );

  target(
    name: 'compile_html_tests',
    agentProfiles: kLinuxAgent,
    runner: testCompilerRunner,
    dependencies: [
      '//:host_debug_unopt_linux',
    ]
  );

  target(
    name: 'compile_canvaskit_tests',
    agentProfiles: kLinuxAgent,
    runner: testCompilerRunner,
    dependencies: [
      '//:host_debug_unopt_linux',
      '//:canvaskit',
    ]
  );

  for (String testType in ['html', 'canvaskit']) {
    for (List<String> agent in [kLinuxAgent, kWindowsAgent, kMacAgent]) {
      for (int shard in [1, 2, 3, 4, 5, 6, 7, 8]) {
        createTestShard(testType, agent, shard);
      }
    }
  }
});

void createTestShard(String testType, List<String> agent, int shard) {
  target(
    name: 'web_tests_${testType}_${shard}_${agent.single}',
    agentProfiles: agent,
    runner: testShardRunner,
    dependencies: [
      ':compile_${testType}_tests',
      '//:host_debug_unopt_${agent.single}',
    ],
  );
}
