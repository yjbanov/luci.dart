# WARNING: assume that nothing explained here actually works.

# luci.dart

`luci.dart` is a small meta-build tool. It allows you to take a single-machine
build to a pool of machines for faster builds. It achieves this by adding
artifact caching, parallelism, and heterogeneity. You describe your build as
a graph of targets that depend on each other. The tool uses the graph to produce
instructions to execute the build on the CI system.

This tool is "meta" because by itself it does not build anything. Instead, it
shells out to other build tools that compile, run tests, etc.

To run this tool you only need the Dart SDK and a few `pub` packages.

This package does not include a CI scheduling system. However, it provides
enough information to the CI system to implement one.

## Features

- **Reusing build artifacts**: if your build contains a step whose results can
  be reused by multiple other steps, this tool offers an API for declaring
  dependencies between build steps, and enumerating build artifacts that the CI
  can archive and pass to other build steps without having to rebuild them
  again.
- **Parallelism**: the tool identifies independent parts of your build and
  allows CI to run them in parallel.
- **Fail fast**: your build may contain trivial tasks that do not take much time
  to run, such as license checkers, analyzers, linters, code formatters. This
  tool can figure out such tasks automatically and run them early. If such a
  task fails the tool can halt the build immediately. This leads to faster
  feedback and better resource utilization. You can use dependencies to ensure
  that a build does not start expensive work until all such smoke tests pass.
- **Heterogeneous build environments**: different pieces of your build may have
  different hardware or OS requirements. For example, one part needs to build
  an APK file, and another part needs to run a test on an Android device, yet
  another needs a Windows machine with Edge. This tool allows you to specify
  such requirements.
- **Serializable build graph**: this tool produces the exact same build graph
  given the same workspace. This allows you to generate the graph (as JSON) and
  store it in a file or a database for other tools to inspect (e.g. dashboards).
  It may also be used to remove a dependency between the CI system and this
  tool. To do that, generate and check in the JSON representation of the graph.
  The CI system can consume the JSON and never need to run this tool.
- **Dart**: if your project uses Dart, this lets you continue using Dart. It
  does not introduce a separate build language (e.g. Skylark).

## Missing features

The following features are not (yet) implemented:

- **Incremental re-builds**: incremental re-builds allow you to only build
  what changed since the last build. To do that your workspace must abide by
  extra rules that this tool does not enforce, such as pre-declaration of
  inputs and outputs for every build target.
- **Target visibility**: all targets have public visibility. Any target may
  depend on any other target.

## Concepts

If you are familiar with [Bazel][2], [GN][3], or other build systems, the
following concepts will sound familiar.

### Target

A target is the smallest piece of work performed by a build. It takes some
configuration parameters, some input files, and produces some output files.
A target _must_ produce the exact same outputs for the same configuration
parameters and inputs.

During a build you _run_ a target. Running a target may either _succeed_ or
_fail_. When a target fails its outputs are discarded.

A build is described as a set of targets. Typically, a target either builds
something (compiles code, gzips artifacts, processes assets), or tests something
(runs tests, runs benchmarks, checks licenses, analyses code). However, targets
may be used for anything that requires running a program that takes some inputs,
and produces some outputs.

### Target runner

A target runner is a reusable piece of code that provides the logic that backs
targets. Multiple targets can use the same target runner by passing it different
configuration and different inputs. For example, you may have a target runner
that compiles C++, builds an APK file, or runs unit tests. A target would
instantiate a runner and configure it for a particular build step.

### Dependencies and the build graph

Targets may _depend_ on each other. A dependency means that one target requires
the outputs of another target. When targets are viewed as vertices and
dependencies are viewed as edges the two form a graph, referred to as the
_build graph_.

The graph must be a directed acyclic graph (DAG) to make sure it is possible to
run targets in a sequence such that every target's dependencies build before
target does.

Dependencies are used to break up the build into smaller chunks for _reuse_,
_parallelism_, and _heterogeneous_ building.

Dependencies can also be used for "smoke tests". For example, you might want to
run code analysis before comitting to a full build. To achieve that, declare
your dependencies such that expensive tasks directly or indirectly depend on
the smoke test.

#### Artifacts

The files a target outputs are called artifacts. Artifacts can be cached and
used as inputs to other targets (using dependencies). The tool will only run
a target once and share the outputs with multiple other targets.

#### Parallelism

Two or more targets that do not depend on each other can run in parallel, thus
speeding up the build.

#### Heterogeneous builds

Sometimes parts of a build contain multiple pieces of work where one piece can
run on a different hardware/OS profile. Examples:

- Build an APK on a powerful Linux server in GCP, then test it on the most
  entry-level Linux computer with an Android device attached to it.
- Compile Web tests to JavaScript on a powerful Linux server, then test it on
  Windows/Edge and macOS/Safari.

Targets can specify what build agent profile they require to run. `luci.dart`
only refers to agent profiles using string identifiers. It knows nothing about
the agents themselves.

Using different agent profiles for each target offers better resource
utilization. For example, you don't have to occupy a 32-core Linux server for
a build step that runs a test on an Android device.

### Workspace

A workspace contains everything needed to construct a build graph and execute
it. Typically one git repository would contain one workspace, but it's not a
requirement.

## Installation

```
pub global activate luci
```

## Command-line usage

All commands assume that they run from within a workspace.

### Listing targets

To list all available targets in the workspace run:

```
luci targets --pretty
```

(`--pretty` makes it easier to read the JSON output)

### Running targets

To run one or more targets run:

```
luci run //path/to:target1 //path/to/another:target2
```

If the specified targets depend on other targets, the tool will run
dependencies prior to running the specified targets.

## Defining a build graph

### Defining a workspace

A workspace is created by adding a `luci_workspace.yaml` to the directory that
contains the code you are interested in building. Typically, this file goes to
the root of the git repository.

The file defines attributes shared by all targets in the workspace. Example:

```yaml
# Workspace name. Required.
name: engine

# Path to the Dart SDK to be used by luci.dart.
#
# This directory is expected to contain bin/dart and bin/pub.
#
# The special value "_ENV_" may be used to indicate that the Dart SDK should
# be derived from the environment variables. `luci.dart` will first attempt to
# use the DART_SDK_PATH environment variable. If that fails it will use `which`
# on Linux and Mac, and `where` on Windows, to find the Dart SDK.
dart_sdk_path: ../out/host_debug_unopt/dart-sdk
```

#### Workspace structure

A workspace is a directory structure with the `luci_workspace.yaml` file in the
top-level directory. That marks all sub-directories as part of the workspace.

Targets are defined in Dart files that must be named `build.luci.dart` using the
Dart programming language. These files are referred to as _build files_. Each
build file defines a flat list of named targets.

Putting the directory and build files together the workspace is a tree of
targets.

Example:

```
/path/to/project/         - the root of your project
  |\ .git
  |\ foo
  |   \ bar
  |     \ build.luci.dart - an example of a build file containing targets
   \ luci_workspace.yaml  - typically this would be at the root of the git repo
```

#### Addressing targets

Targets are addressed via workspace-relative paths. The root of the workspace
is denoted by two slashes - `//`. In the example above this would correspond to
the `/path/to/project` directory. It is followed by OS-independent path schema
that follows the directory structure. The path must terminate at a directory
containing a build file, e.g. `//foo/bar` corresponds to the
`/path/to/project/foo/bar/build.luci.dart` build file. Finally, the name of the
target is specified after a semicolon, e.g. `//foo/bar:widget_tests` corresponds
to the target named `widget_tests` declared in the build file.

### Defining targets

Targets are defined using the Dart programming language in `build.luci.dart`
files that import `package:luci/build.dart`. This library provides two functions
`build` and `target`.

Example:

```dart
// Brings the API for declaring targets. Imported by every `build.luci.dart` file.
import 'package:luci/build.dart';

// A local library that supplies `TargetRunner` implementations, such as
// `WebUnitTestRunner` and `WebCheckLicensesRunner` used in this file.
// It's the `build.luci.dart` file's decision where to get the implementations
// of target runners. Use idiomatic Dart to decide that.
import 'web_runners.dart';

/// In this example `main` immediately calls `build`, but it's not required.
/// A build file is free to run code before and after `build`. However, build
/// files communicate with the `luci` tool via standard output. If a build file
/// needs to run custom code, make sure it does not write to standard output.
///
/// Unless it is requested to run a target, a build file is expected finish
/// quickly (~1-2 milliseconds). This ensures that workspace builds are fast.
void main(List<String> args) => build(args, () {
  // Declares a target that compiles unit-tests in this package.
  target(
    name: 'unit_test_dart2js',
    agentProfiles: kLinuxAgent,
    runner: WebTestCompiler(sources: ['test/**/*.dart']),
  );

  // Declares a tartget that runs unit-tests on Linux using Chrome.
  //
  // Notice that this task has a dependency on the 'unit_test_dart2js' target
  // declared above. This is an example of how targets can be used to separate
  // building from testing. This can be used for reusing build artifacts (the
  // next target uses the same outputs by depending on the same target). We
  // therefore only need to compile tests once.
  target(
    name: 'unit_tests_linux_chrome',
    agentProfiles: kLinuxAgent,
    runner: WebUnitTestRunner(
      browser: 'chrome',
    ),
    environment: {
      'CHROME_NO_SANDBOX': 'true',
    },
    dependencies: [
      // A local dependency points to another target in the same build file.
      ':unit_test_dart2js',
      // Dependencies can point anywhere in the workspace using
      // workspace-relative paths.
      '//lib/web_ui:chrome',
      // An example of a dependency used to make sure that this target runs
      // after the license check smoke test.
      ':check_licenses',
    ],
  );

  // Declares a tartget that runs unit-tests on Windows using Edge.
  //
  // Notice that this target requires a Windows agent, but it depends on a
  // target that uses Linux. This is an example of a heterogeneous build. It
  // also demonstrates how builds can be parallelized: the `unit_tests_linux_chrome`
  // and `unit_tests_windows_edge` can run in parallel.
  target(
    name: 'unit_tests_windows_edge',
    agentProfiles: kWindowsAgent,
    runner: WebUnitTestRunner(
      browser: 'edge',
    ),
    dependencies: [
      ':unit_test_dart2js',
    ],
  );

  // Declares a target that checks license headers in Web engine sources.
  //
  // Because this target does not depend on anything, it can run early and in
  // parallel with other targets. This allows the build to fail fast.
  target(
    name: 'check_licenses',
    agentProfiles: kLinuxAgent,
    runner: WebCheckLicensesRunner(),
  );
});
```

[1]: https://github.com/luci
[2]: https://bazel.build
[3]: https://chromium.googlesource.com/chromium/src/tools/gn/+/48062805e19b4697c5fbd926dc649c78b6aaa138/README.md
