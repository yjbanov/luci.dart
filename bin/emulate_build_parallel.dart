// Copyright 2013 The Flutter Authors. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

/// Runs all targest in the workspace in parallel.
///
/// Uses an imaginary pool of Linux, Windows, and macOS machines.

// @dart = 2.6
import 'dart:async';
import 'dart:collection';
import 'dart:io' as io;

import 'package:luci/src/process.dart';
import 'package:luci/src/workspace.dart';

// const int linuxCount = 1;
// const int windowsCount = 1;
// const int macCount = 1;

// const int linuxCount = 2;
// const int windowsCount = 2;
// const int macCount = 2;

const int linuxCount = 4;
const int windowsCount = 4;
const int macCount = 4;

// const int linuxCount = 8;
// const int windowsCount = 8;
// const int macCount = 8;

Future<void> main(List<String> args) async {
  await initializeWorkspaceConfiguration();
  await Scheduler(await resolveBuildGraph()).build();
}

/// A pool of build agents.
final Map<String, List<Agent>> agents = <String, List<Agent>>{
  'linux': List<Agent>.generate(linuxCount, (int i) => Agent('linux #$i')),
  'windows': List<Agent>.generate(windowsCount, (int i) => Agent('windows #$i')),
  'mac': List<Agent>.generate(macCount, (int i) => Agent('mac #$i')),
};

final Map<String, AgentPool> agentPools = agents.map((key, value) =>
    MapEntry<String, AgentPool>(key, AgentPool(value)));

/// Schedules targets on pools of build agents.
class Scheduler {
  Scheduler(BuildGraph graph) : _pendingTargets = graph.targetsInDependencyOrder.toList();

  final List<WorkspaceTarget> _pendingTargets;
  final List<WorkspaceTarget> _runningTargets = <WorkspaceTarget>[];
  final Set<TargetPath> _completedTargets = <TargetPath>{};
  final Completer<void> _buildCompleter = Completer<void>();

  final HtmlReport report = HtmlReport(agents);

  /// Builds the entire build graph.
  Future<void> build() async {
    print('Building ${_pendingTargets.length} targets.');
    final Stopwatch stopwatch = Stopwatch()..start();
    _scheduleAvailableTargets();
    await _buildCompleter.future;
    stopwatch.stop();
    await io.File('report.html').writeAsString(report.getReport(stopwatch.elapsed));
  }

  /// Finds targets whose dependencies are satisfied and schedules them to be run
  /// on build agents.
  void _scheduleAvailableTargets() {
    if (_pendingTargets.isEmpty && _runningTargets.isEmpty) {
      print('All targets completed.');
      _buildCompleter.complete();
    }
    final List<WorkspaceTarget> readyTargets = _pendingTargets.where(_hasDependenciesSatisfied).toList();
    if (readyTargets.isNotEmpty) {
      readyTargets.forEach((WorkspaceTarget target) {
        _scheduleOnAgent(target);
      });
    }
  }

  DateTime _buildStartTime = DateTime.now();

  /// Waits for the next available agent and schedules a target on it.
  ///
  /// Assumes the target's dependencies are satisfied.
  void _scheduleOnAgent(WorkspaceTarget target) async {
    _pendingTargets.remove(target);
    _runningTargets.add(target);
    final String agentProfile = agents.keys.firstWhere(
      target.buildTarget.agentProfiles.contains,
      orElse: () {
        throw StateError(
          'Target ${target.path} requested unknown agent profile: '
          '${target.buildTarget.agentProfiles.join(', ')}',
        );
      },
    );
    final AgentPool pool = agentPools[agentProfile];
    final Agent agent = await pool.request();
    final DateTime startTime = DateTime.now();
    final bool isSuccess = await agent.runTarget(target);
    _runningTargets.remove(target);
    if (isSuccess) {
      print('Finished ${target.path}');
      _completedTargets.add(target.path);
      _scheduleAvailableTargets();
    } else {
      _buildCompleter.completeError('Target ${target.path} failed');
    }

    final DateTime endTime = DateTime.now();
    report.recordTargetRuntime(
      agent,
      target,
      startTime.difference(_buildStartTime),
      endTime.difference(startTime),
    );
    pool.release(agent);
  }

  bool _hasDependenciesSatisfied(WorkspaceTarget target) {
    return _completedTargets.containsAll(target.dependencies.map((t) => t.path));
  }
}

/// Visualizes the build job in HTML.
class HtmlReport {
  HtmlReport(Map<String, List<Agent>> agents) {
    agents.forEach((key, value) {
      this.agents.addAll(value);
    });
    drawAgents();
  }

  static const double columnWidth = 200.0;

  final StringBuffer buf = StringBuffer('''
  <style>
    * {
      font-size: 12px;
      font-family: monospace;
      word-wrap: break-word;
    }
    rect {
      position: absolute;
      border: 1px solid black;
      text-align: center;
    }
  </style>
  <body>
  ''');

  final List<Agent> agents = <Agent>[];

  String getReport(Duration totalBuildDuration) {
    Duration totalCpuTime = agents.map((a) => a.usage).reduce((value, element) => value + element);
    buf.writeln(
      '''
      <div style="position: fixed; bottom: 10px; right: 10px; background-color: rgba(100, 255, 100, 0.4); font-size: 24px">
        <b>
        <p>Total build took
        ${(totalBuildDuration.inMilliseconds / 1000).toStringAsFixed(1)} seconds</p>
        <p>CPU time used
        ${(totalCpuTime.inMilliseconds / 1000).toStringAsFixed(1)} seconds
        </b>
      </div>
      </body>
      '''
    );
    return buf.toString();
  }

  void drawAgents() {
    for (int i = 0; i < agents.length; i++) {
      final Agent agent = agents[i];
      drawRectWithText(
        agent,
        2.0,
        26.0,
        '<b>${agent.name}</b>',
        color: 'rgba(100, 255, 100, 0.5)',
      );
    }
  }

  double durationToY(Duration duration) {
    return 50.0 * duration.inMilliseconds / 1000;
  }

  void recordTargetRuntime(Agent agent, WorkspaceTarget target, Duration startTime, Duration duration) {
    drawRectWithText(
      agent,
      35.0 + durationToY(startTime),
      durationToY(duration),
      target.buildTarget.name,
    );
  }

  void drawRectWithText(Agent agent, double start, double height, String text, { String color: '#FFFFFF'}) {
    final int i = agents.indexOf(agent);
    final double left = columnWidth * i + 2.0;
    buf.writeln('''
    <rect style="left: ${left}px; top: ${start}px; height: ${height}px; width: ${columnWidth - 4.0}px; background-color: ${color}">
      <p style="position: absolute; top: ${height / 2 - 6}px; margin: 0; text-align: center; width:100%">
        $text
      </p>
    </rect>
    ''');
  }
}

class AgentPool {
  final List<Agent> _availableAgents;
  final List<Agent> _allocatedAgents = <Agent>[];

  AgentPool(List<Agent> agents) : _availableAgents = agents.toList();

  final DoubleLinkedQueue<Completer<void>> _pendingRequests = DoubleLinkedQueue<Completer<void>>();

  FutureOr<Agent> request() async {
    while (_availableAgents.isEmpty) {
      final Completer<void> pendingRequest = Completer<void>();
      _pendingRequests.add(pendingRequest);
      await pendingRequest.future;
    }
    final Agent agent = _availableAgents.removeLast();
    agent.allocate();
    _allocatedAgents.add(agent);
    return agent;
  }

  void release(Agent agent) {
    agent.release();
    _allocatedAgents.remove(agent);
    _availableAgents.add(agent);
    if (_pendingRequests.isNotEmpty) {
      _pendingRequests.removeFirst().complete();
    }
  }
}

class Agent {
  final String name;
  Agent(this.name);

  Duration usage = Duration.zero;

  Stopwatch allocationTimer;

  void allocate() {
    allocationTimer = Stopwatch()..start();
  }

  void release() {
    allocationTimer.stop();
    usage += allocationTimer.elapsed;
    allocationTimer = null;
  }

  Future<bool> runTarget(WorkspaceTarget target) async {
    print('Running ${target.path}');
    final io.File buildFile = io.File(target.path.toBuildFilePath(workspaceConfiguration.rootDirectory));
    final io.Process targetProcess = await startProcess(
      workspaceConfiguration.dartExecutable,
      <String>[buildFile.path, 'run', target.buildTarget.name],
      workingDirectory: buildFile.parent.path,
    );
    final int exitCode = await targetProcess.exitCode;
    return exitCode == 0;
  }
}
