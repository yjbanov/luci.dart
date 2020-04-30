// Copyright 2013 The Flutter Authors. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

// @dart = 2.6
import 'package:args/command_runner.dart';

/// Adds utility methods to [Command] classes for parsing arguments.
mixin ArgUtils<T> on Command<T> {
  /// Extracts a boolean argument from [argResults].
  bool boolArg(String name) => argResults[name] as bool;

  /// Extracts a string argument from [argResults].
  String stringArg(String name) => argResults[name] as String;

  /// Extracts a integer argument from [argResults].
  ///
  /// If the argument value cannot be parsed as [int] throws an [ArgumentError].
  int intArg(String name) {
    final String rawValue = stringArg(name);
    if (rawValue == null) {
      return null;
    }
    final int value = int.tryParse(rawValue);
    if (value == null) {
      throw ArgumentError(
        'Argument $name should be an integer value but was "$rawValue"',
      );
    }
    return value;
  }
}
