// Copyright 2013 The Flutter Authors. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

import 'package:luci/build.dart';

final DemoRunner hostDebugUnoptRunner = DemoRunner(const Duration(seconds: 8));
final DemoRunner canvasKitRunner = DemoRunner(const Duration(seconds: 5));
final DemoRunner testCompilerRunner = DemoRunner(const Duration(seconds: 8));
final DemoRunner licenseCheckRunner = DemoRunner(const Duration(seconds: 1));
final DemoRunner testShardRunner = DemoRunner(const Duration(seconds: 2));

class DemoRunner implements TargetRunner {
  DemoRunner(this.duration);

  final Duration duration;

  @override
  Future<void> run(Target target) async {
    final String agent = target.agentProfiles.single;
    final Duration runtime = agent == 'linux'
      ? duration
      : agent == 'mac'
        ? duration * 1.5
        : duration * 3;
    await Future<void>.delayed(runtime * 0.2);
  }
}
