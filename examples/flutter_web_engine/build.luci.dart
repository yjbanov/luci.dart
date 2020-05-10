// Copyright 2013 The Flutter Authors. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

// @dart = 2.6
import 'package:luci/build.dart';

import 'runners.dart';

void main(List<String> args) => build(args, () {
  target(
    name: 'host_debug_unopt_linux',
    agentProfiles: kLinuxAgent,
    runner: hostDebugUnoptRunner,
  );

  target(
    name: 'host_debug_unopt_windows',
    agentProfiles: kWindowsAgent,
    runner: hostDebugUnoptRunner,
  );

  target(
    name: 'host_debug_unopt_mac',
    agentProfiles: kMacAgent,
    runner: hostDebugUnoptRunner,
  );

  target(
    name: 'canvaskit',
    agentProfiles: kLinuxAgent,
    runner: canvasKitRunner,
  );
});
