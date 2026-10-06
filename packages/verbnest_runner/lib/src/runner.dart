import 'dart:async';

import 'package:verbnest_core/verbnest_core.dart';
import 'package:verbnest_storage/verbnest_storage.dart';

/// Longest chain of `setNextRequest` jumps allowed before the run gives up,
/// so a script that points at itself cannot run forever.
const maxRunSteps = 10000;

/// What to run (FR-RUN-001).
class RunConfig {
  const RunConfig({
    required this.name,
    required this.requestIds,
    this.iterations = 1,
    this.delay = Duration.zero,
    this.stopOnFailure = false,
    this.data = const [],
    this.maxSteps = maxRunSteps,
  });

  final String name;

  /// In run order. Hand-picked and reordered lists are fine.
  final List<String> requestIds;
  final int iterations;
  final Duration delay;
  final bool stopOnFailure;

  /// One row per iteration; when set it decides the iteration count.
  final List<DataRow> data;

  /// Requests run in total before giving up; see [maxRunSteps].
  final int maxSteps;

  int get totalIterations => data.isEmpty ? iterations : data.length;
}

/// Every HTTP request below [containerId], depth first in tree order.
List<NodeInfo> requestsUnder(WorkspaceRepository repo, String containerId) {
  final out = <NodeInfo>[];
  void walk(String id) {
    for (final n in repo.children(id)) {
      if (n.isContainer) {
        walk(n.id);
      } else if (n.type == 'http') {
        out.add(n);
      }
    }
  }

  walk(containerId);
  return out;
}

/// How a step asks the run to continue.
class RunFlow {
  const RunFlow({this.next, this.stop = false, this.skip = false});

  /// Name of the request to run next, or null for the natural order.
  final String? next;
  final bool stop;
  final bool skip;
}

class RunStepResult {
  const RunStepResult(this.entry, [this.flow = const RunFlow()]);

  final RunEntry entry;
  final RunFlow flow;
}

class RunProgress {
  const RunProgress({
    required this.entries,
    required this.iteration,
    required this.total,
    this.currentName,
  });

  final List<RunEntry> entries;
  final int iteration;
  final int total;
  final String? currentName;
}

/// Sends one request of a run. The app answers with its editor (scripts and
/// all); the CLI with [HeadlessSender].
typedef RunStep = Future<RunStepResult> Function(
  String id,
  String name,
  int iteration,
  Map<String, String> row,
);

/// Runs [config] by calling [step] for each request, handling iterations,
/// data rows, delays, `setNextRequest` jumps and stop conditions.
/// [shouldStop] is polled before each request.
Future<RunReport> executeRun({
  required RunConfig config,
  required WorkspaceRepository repo,
  required RunStep step,
  bool Function()? shouldStop,
  void Function(RunProgress progress)? onProgress,
  String? environment,
}) async {
  bool stopped() => shouldStop?.call() ?? false;
  final started = DateTime.now();
  final iterations = config.totalIterations;
  final entries = <RunEntry>[];
  var stoppedEarly = false;
  var steps = 0;

  iterationLoop:
  for (var it = 1; it <= iterations; it++) {
    final row = config.data.isEmpty
        ? const <String, String>{}
        : config.data[it - 1];
    final names = [for (final id in config.requestIds) repo.node(id).name];
    var i = 0;
    while (i < config.requestIds.length) {
      if (stopped() || ++steps > config.maxSteps) {
        stoppedEarly = true;
        break iterationLoop;
      }
      onProgress?.call(
        RunProgress(
          entries: List.of(entries),
          iteration: it,
          total: iterations,
          currentName: names[i],
        ),
      );
      final result = await step(config.requestIds[i], names[i], it, row);
      var entry = result.entry;
      final flow = result.flow;
      final next = flow.next;
      final jump = next == null ? null : names.indexOf(next);
      final badJump = jump == -1;
      if (badJump) {
        entry = entry.withError(
          'setNextRequest: no request named "$next" in this run',
        );
      }
      entries.add(entry);
      onProgress?.call(
        RunProgress(
          entries: List.of(entries),
          iteration: it,
          total: iterations,
        ),
      );
      if (stopped() ||
          (config.stopOnFailure && !entry.ok && !flow.skip) ||
          flow.stop ||
          badJump) {
        stoppedEarly = true;
        break iterationLoop;
      }
      i = jump ?? i + 1;
      if (config.delay > Duration.zero &&
          (i < config.requestIds.length || it < iterations)) {
        await Future<void>.delayed(config.delay);
      }
    }
  }
  return RunReport(
    name: config.name,
    startedAt: started,
    finishedAt: DateTime.now(),
    environment: environment,
    iterations: iterations,
    entries: entries,
    stoppedEarly: stoppedEarly,
  );
}
