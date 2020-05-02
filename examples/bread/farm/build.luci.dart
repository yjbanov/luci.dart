// Copyright 2013 The Flutter Authors. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

// @dart = 2.6
import 'dart:io' as io;
import 'package:luci/build.dart';

void main(List<String> args) => build(args, () {
  target(
    name: 'water',
    agentProfiles: kLinuxAgent,
    runner: Farmer(),
  );

  target(
    name: 'seeds',
    agentProfiles: kLinuxAgent,
    runner: Farmer(),
  );

  target(
    name: 'compost',
    agentProfiles: kLinuxAgent,
    runner: Farmer(),
  );

  target(
    name: 'wheat',
    agentProfiles: kLinuxAgent,
    runner: Farmer(),
    dependencies: [
      ':water',
      ':seeds',
      ':compost',
    ],
  );
});

class Farmer implements TargetRunner {
  @override
  Future<void> run(Target target) async {
    await io.File('build/${target.name}').writeAsString('Output for ${target.name}');
  }
}
