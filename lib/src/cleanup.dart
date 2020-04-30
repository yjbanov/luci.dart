// Copyright 2013 The Flutter Authors. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

// @dart = 2.6

/// A function that performs asynchronous work.
typedef AsyncCallback = Future<void> Function();

final List<AsyncCallback> _cleanupCallbacks = <AsyncCallback>[];

/// Add a [callback] to be called before exiting the `luci.dart` process.
///
/// Use this to cleanup dangling processes, close open browsers, delete temp
/// files, etc.
void scheduleCleanup(AsyncCallback callback) {
  _cleanupCallbacks.add(callback);
}

/// Calls callbacks scheduled via [scheduleCleanup].
Future<void> cleanup() async {
  for (AsyncCallback callback in _cleanupCallbacks) {
    await callback.call();
  }
}
