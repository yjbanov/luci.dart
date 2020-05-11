// Copyright 2013 The Flutter Authors. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

// @dart = 2.6
import 'dart:io' as io;
import 'package:luci/build.dart';

void main(List<String> args) => build(args, () {
  target(
    name: 'flour',
    agentProfiles: kLinuxAgent,
    runner: Windmill(),
    dependencies: [
      '//farm:wheat',
    ],
  );
});

class Windmill implements TargetRunner {
  @override
  Future<void> run(Target target) async {
    await io.Directory('build').create();
    await io.File('build/${target.name}').writeAsString('Output for ${target.name}');
  }
}
