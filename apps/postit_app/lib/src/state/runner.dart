import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:postit_core/postit_core.dart';
import 'package:postit_runner/postit_runner.dart';

import '../scripting/script_io.dart' show ScriptFlow;
import 'editor_state.dart';
import 'session.dart';
import 'variables.dart';

export 'package:postit_runner/postit_runner.dart'
    show RunConfig, requestsUnder, maxRunSteps;

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

  Future<RunStepResult> _send(
    String id,
    String name,
    int iteration,
    Map<String, String> row,
  ) async {
    _activeId = id;
    await ref.read(editorProvider(id).notifier).send(force: true, data: row);
    _activeId = null;
    final s = ref.read(editorProvider(id));
    final r = s.response;
    final error = s.error ?? s.scriptError;
    final ScriptFlow flow = s.flow;
    return RunStepResult(
      RunEntry(
        iteration: iteration,
        requestId: id,
        name: name,
        method: s.item.method,
        url: r?.sent.url.toString() ?? s.item.url,
        status: r?.status,
        reason: r?.reason ?? '',
        timeMs: r?.timings.total.inMilliseconds ?? 0,
        tests: s.tests,
        error: _stop && error != null ? 'Stopped' : error,
        skipped: flow.skip,
      ),
      RunFlow(next: flow.next, stop: flow.stop, skip: flow.skip),
    );
  }

  Future<RunReport> run(RunConfig config) async {
    final session = ref.read(sessionProvider);
    final envId = ref.read(activeEnvProvider);
    final envName = envId == null
        ? null
        : session.repo
              .environments()
              .where((e) => e.id == envId)
              .firstOrNull
              ?.name;
    _stop = false;
    state = RunnerState(running: true, total: config.totalIterations);
    final report = await executeRun(
      config: config,
      repo: session.repo,
      step: _send,
      shouldStop: () => _stop,
      environment: envName,
      onProgress: (p) => state = RunnerState(
        running: true,
        entries: p.entries,
        iteration: p.iteration,
        total: p.total,
        currentName: p.currentName,
      ),
    );
    state = RunnerState(
      entries: report.entries,
      report: report,
      iteration: report.iterations,
      total: report.iterations,
    );
    return report;
  }
}

final runnerProvider = NotifierProvider<RunnerNotifier, RunnerState>(
  RunnerNotifier.new,
);
