import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:postit_core/postit_core.dart';
import 'package:postit_storage/postit_storage.dart';

import 'editor_state.dart';
import 'session.dart';
import 'variables.dart';

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

class RunnerState {
  const RunnerState({
    this.running = false,
    this.entries = const [],
    this.report,
    this.iteration = 0,
    this.total = 0,
    this.currentName,
  });

  final bool running;
  final List<RunEntry> entries;

  /// Set when a run finishes or is stopped.
  final RunReport? report;
  final int iteration;
  final int total;
  final String? currentName;
}

/// Longest chain of `setNextRequest` jumps allowed before the run gives up,
/// so a script that points at itself cannot run forever.
const maxRunSteps = 10000;

class RunnerNotifier extends Notifier<RunnerState> {
  bool _stop = false;
  String? _activeId;

  @override
  RunnerState build() => const RunnerState();

  void stop() {
    _stop = true;
    final id = _activeId;
    if (id != null) ref.read(editorProvider(id).notifier).cancel();
  }

  void clear() {
    if (!state.running) state = const RunnerState();
  }

  Future<RunReport> run(RunConfig config) async {
    final session = ref.read(sessionProvider);
    final repo = session.repo;
    final envId = ref.read(activeEnvProvider);
    final envName = envId == null
        ? null
        : repo.environments().where((e) => e.id == envId).firstOrNull?.name;
    final started = DateTime.now();
    final iterations = config.totalIterations;
    final entries = <RunEntry>[];
    _stop = false;
    var stoppedEarly = false;
    var steps = 0;
    state = RunnerState(running: true, total: iterations);

    iterationLoop:
    for (var it = 1; it <= iterations; it++) {
      final row = config.data.isEmpty
          ? const <String, String>{}
          : config.data[it - 1];
      final names = [for (final id in config.requestIds) repo.node(id).name];
      var i = 0;
      while (i < config.requestIds.length) {
        if (_stop || ++steps > config.maxSteps) {
          stoppedEarly = true;
          break iterationLoop;
        }
        final id = config.requestIds[i];
        _activeId = id;
        state = RunnerState(
          running: true,
          entries: List.of(entries),
          iteration: it,
          total: iterations,
          currentName: names[i],
        );
        final notifier = ref.read(editorProvider(id).notifier);
        await notifier.send(force: true, data: row);
        _activeId = null;
        final s = ref.read(editorProvider(id));
        final r = s.response;
        final error = s.error ?? s.scriptError;
        entries.add(
          RunEntry(
            iteration: it,
            requestId: id,
            name: names[i],
            method: s.item.method,
            url: r?.sent.url.toString() ?? s.item.url,
            status: r?.status,
            reason: r?.reason ?? '',
            timeMs: r?.timings.total.inMilliseconds ?? 0,
            tests: s.tests,
            error: _stop && error != null ? 'Stopped' : error,
            skipped: s.flow.skip,
          ),
        );
        state = RunnerState(
          running: true,
          entries: List.of(entries),
          iteration: it,
          total: iterations,
        );
        if (_stop) {
          stoppedEarly = true;
          break iterationLoop;
        }
        if (config.stopOnFailure && !entries.last.ok && !s.flow.skip) {
          stoppedEarly = true;
          break iterationLoop;
        }
        if (s.flow.stop) {
          stoppedEarly = true;
          break iterationLoop;
        }
        final next = s.flow.next;
        if (next != null) {
          final j = names.indexOf(next);
          if (j == -1) {
            entries[entries.length - 1] = RunEntry(
              iteration: it,
              requestId: id,
              name: names[i],
              method: entries.last.method,
              url: entries.last.url,
              status: entries.last.status,
              reason: entries.last.reason,
              timeMs: entries.last.timeMs,
              tests: entries.last.tests,
              error: 'setNextRequest: no request named "$next" in this run',
            );
            stoppedEarly = true;
            break iterationLoop;
          }
          i = j;
        } else {
          i++;
        }
        if (config.delay > Duration.zero &&
            (i < config.requestIds.length || it < iterations)) {
          await Future<void>.delayed(config.delay);
        }
      }
    }
    final report = RunReport(
      name: config.name,
      startedAt: started,
      finishedAt: DateTime.now(),
      environment: envName,
      iterations: iterations,
      entries: entries,
      stoppedEarly: stoppedEarly,
    );
    state = RunnerState(
      entries: entries,
      report: report,
      iteration: iterations,
      total: iterations,
    );
    return report;
  }
}

final runnerProvider = NotifierProvider<RunnerNotifier, RunnerState>(
  RunnerNotifier.new,
);
