// Copyright 2013 The Flutter Authors. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

// @dart = 2.6
import 'dart:io' as io;
import 'package:luci/build.dart';

// This build file contains cycles.
void main(List<String> args) => build(args, () {
  target(
    name: 'foo',
    agentProfiles: kLinuxAgent,
    runner: NoopRunner(),
    dependencies: [
      '//bar:bar',
    ]
  );
});

class NoopRunner implements TargetRunner {
  @override
  Future<void> run(Target target) async {
    await io.File('build/${target.name}').writeAsString('Output for ${target.name}');
  }
}
