import 'dart:convert';
import 'dart:typed_data';

import 'package:material_ui/material_ui.dart' hide DataRow;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:verbnest_core/verbnest_core.dart';

import '../state/file_port.dart';
import '../state/runner.dart';
import '../state/session.dart';
import '../theme.dart';
import '../widgets/mock_server_dialog.dart';
import '../../l10n/l10n.dart';
import '../layout_class.dart';
import '../widgets/ui/toast.dart';
import '../widgets/ui/ui.dart';

/// Runs the requests of a collection or folder in order (FR-RUN-001) and
/// shows the results as they arrive (FR-RUN-002).
class RunnerPage extends ConsumerStatefulWidget {
  const RunnerPage({super.key, required this.containerId});

  final String containerId;

  @override
  ConsumerState<RunnerPage> createState() => _RunnerPageState();
}

class _Pick {
  _Pick(this.id, this.name, this.method);
  final String id;
  final String name;
  final String? method;
  bool on = true;
}

class _RunnerPageState extends ConsumerState<RunnerPage> {
  late final List<_Pick> _picks;
  late final String _title;
  int _iterations = 1;
  int _delayMs = 0;
  bool _stopOnFailure = false;
  List<DataRow> _data = const [];
  String? _dataName;
  String? _dataError;

  @override
  void initState() {
    super.initState();
    final repo = ref.read(sessionProvider).repo;
    _title = repo.node(widget.containerId).name;
    _picks = [
      for (final n in requestsUnder(repo, widget.containerId))
        _Pick(n.id, n.name, n.method),
    ];
    // A previous finished run of another container must not linger.
    Future.microtask(() => ref.read(runnerProvider.notifier).clear());
  }

  Future<void> _pickData() async {
    final f = await ref.read(filePortProvider).pick();
    if (f == null) return;
    try {
      final rows = parseDataFile(
        utf8.decode(f.bytes, allowMalformed: true),
        fileName: f.name,
      );
      setState(() {
        _data = rows;
        _dataName = f.name;
        _dataError = rows.isEmpty ? context.l10n.runNoRows : null;
      });
    } on FormatException catch (e) {
      setState(() {
        _data = const [];
        _dataName = null;
        _dataError = e.message;
      });
    }
  }

  Future<void> _start() async {
    final ids = [
      for (final p in _picks)
        if (p.on) p.id,
    ];
    if (ids.isEmpty) return;
    await ref
        .read(runnerProvider.notifier)
        .run(
          RunConfig(
            name: _title,
            requestIds: ids,
            iterations: _iterations,
            delay: Duration(milliseconds: _delayMs),
            stopOnFailure: _stopOnFailure,
            data: _data,
          ),
        );
  }

  Future<void> _export(RunReport report, String kind) async {
    final (ext, text, mime) = switch (kind) {
      'junit' => ('xml', report.toJUnit(), 'application/xml'),
      'html' => ('html', report.toHtml(), 'text/html'),
      _ => (
        'json',
        const JsonEncoder.withIndent('  ').convert(report.toJson()),
        'application/json',
      ),
    };
    final ok = await ref
        .read(filePortProvider)
        .save(
          '${safeFileName(report.name)}-run.$ext',
          Uint8List.fromList(utf8.encode(text)),
          mime: mime,
        );
    if (ok && mounted) {
      showToast(context, context.l10n.runReportSaved);
    }
  }

  @override
  Widget build(BuildContext context) {
    final run = ref.watch(runnerProvider);
    return Scaffold(
      appBar: AppBar(
        title: Text(context.l10n.runTitle(_title)),
        actions: [
          TextButton(
            key: const Key('mock-server'),
            onPressed: () => showDialog<void>(
              context: context,
              builder: (_) => UncontrolledProviderScope(
                container: ProviderScope.containerOf(context),
                child: MockServerDialog(containerId: widget.containerId),
              ),
            ),
            child: Text(context.l10n.mockTitle),
          ),
        ],
      ),
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // The setup scrolls inside a share of the screen, so a short window
          // keeps room for the results.
          if (!run.running)
            ConstrainedBox(
              constraints: BoxConstraints(
                maxHeight: MediaQuery.sizeOf(context).height * 0.45,
              ),
              child: SingleChildScrollView(child: _setup(context)),
            ),
          if (!run.running) _startBar(context),
          if (run.running) _progress(context, run),
          const Divider(height: 1),
          Expanded(child: _results(context, run)),
          if (run.report != null) _summary(context, run.report!),
        ],
      ),
    );
  }

  Widget _setup(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          ConstrainedBox(
            constraints: BoxConstraints(
              maxHeight: (MediaQuery.sizeOf(context).height * 0.3).clamp(
                96.0,
                220.0,
              ),
            ),
            child: _pickList(context),
          ),
          _options(context),
          if (_dataError != null)
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Text(
                _dataError!,
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
            ),
        ],
      ),
    );
  }

  Widget _pickList(BuildContext context) {
    if (_picks.isEmpty) {
      return EmptyState(
        icon: Icons.playlist_remove,
        title: context.l10n.runNoRequests,
      );
    }
    return ReorderableListView(
      key: const Key('run-requests'),
      buildDefaultDragHandles: true,
      onReorderItem: (from, to) => setState(() {
        _picks.insert(to, _picks.removeAt(from));
      }),
      children: [
        for (final p in _picks)
          CheckboxListTile(
            key: ValueKey(p.id),
            dense: true,
            value: p.on,
            onChanged: (v) => setState(() => p.on = v ?? true),
            title: Text(
              '${p.method ?? ''}  ${p.name}',
              overflow: TextOverflow.ellipsis,
            ),
          ),
      ],
    );
  }

  Widget _options(BuildContext context) {
    return Wrap(
      spacing: 12,
      runSpacing: 8,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        SizedBox(
          width: 110,
          child: TextFormField(
            key: const Key('run-iterations'),
            initialValue: '$_iterations',
            enabled: _data.isEmpty,
            keyboardType: TextInputType.number,
            decoration: InputDecoration(
              labelText: context.l10n.runIterations,
              isDense: true,
            ),
            onChanged: (v) =>
                _iterations = (int.tryParse(v) ?? 1).clamp(1, 10000),
          ),
        ),
        SizedBox(
          width: 130,
          child: TextFormField(
            key: const Key('run-delay'),
            initialValue: '$_delayMs',
            keyboardType: TextInputType.number,
            decoration: InputDecoration(
              labelText: context.l10n.runDelay,
              isDense: true,
            ),
            onChanged: (v) =>
                _delayMs = (int.tryParse(v) ?? 0).clamp(0, 600000),
          ),
        ),
        FilterChip(
          key: const Key('run-stop-on-failure'),
          label: Text(context.l10n.runStopOnFailure),
          selected: _stopOnFailure,
          onSelected: (v) => setState(() => _stopOnFailure = v),
        ),
        OutlinedButton.icon(
          key: const Key('run-data'),
          onPressed: _pickData,
          icon: const Icon(Icons.table_chart_outlined),
          label: Text(
            _dataName == null
                ? context.l10n.runDataFile
                : context.l10n.runDataFileRows(_dataName!, _data.length),
          ),
        ),
        if (_dataName != null)
          IconButton(
            tooltip: context.l10n.runRemoveData,
            icon: const Icon(Icons.close, size: 18),
            onPressed: () => setState(() {
              _data = const [];
              _dataName = null;
            }),
          ),
      ],
    );
  }

  /// The primary action stays below the scrolling setup, so it is on screen
  /// however short the window is.
  Widget _startBar(BuildContext context) {
    final compact =
        MediaQuery.sizeOf(context).width < LayoutClass.mediumBreakpoint;
    final button = FilledButton.icon(
      key: const Key('run-start'),
      onPressed: _picks.any((p) => p.on) ? _start : null,
      icon: const Icon(Icons.play_arrow),
      label: Text(context.l10n.runStart),
    );
    return Padding(
      padding: const EdgeInsets.fromLTRB(8, 0, 8, 8),
      child: compact
          ? SizedBox(width: double.infinity, child: button)
          : Align(alignment: AlignmentDirectional.centerEnd, child: button),
    );
  }

  Widget _progress(BuildContext context, RunnerState run) => Padding(
    padding: const EdgeInsets.all(8),
    child: Row(
      children: [
        SizedBox(
          width: 28,
          height: 28,
          child: Stack(
            alignment: Alignment.center,
            children: [
              CircularProgressIndicator(
                strokeWidth: 3,
                // Iterations advance in steps; between them the ring spins.
                value: run.total == 0 ? null : run.iteration / run.total,
              ),
              Text(
                run.total == 0
                    ? ''
                    : '${(100 * run.iteration / run.total).round()}',
                style: const TextStyle(fontSize: 8),
              ),
            ],
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Text(
            '${context.l10n.runProgress(run.iteration, run.total)}'
            '${run.currentName == null ? '' : ' · ${run.currentName}'}',
            key: const Key('run-progress'),
          ),
        ),
        OutlinedButton(
          key: const Key('run-stop'),
          onPressed: ref.read(runnerProvider.notifier).stop,
          child: Text(context.l10n.runStop),
        ),
      ],
    ),
  );

  Widget _results(BuildContext context, RunnerState run) {
    if (run.entries.isEmpty) {
      return EmptyState(
        icon: Icons.play_circle_outline,
        title: context.l10n.runResultsHere,
      );
    }
    return ListView(
      key: const Key('run-results'),
      children: [for (final e in run.entries) _entryTile(context, run, e)],
    );
  }

  Widget _entryTile(BuildContext context, RunnerState run, RunEntry e) {
    final scheme = Theme.of(context).colorScheme;
    return ExpansionTile(
      leading: Icon(
        e.skipped
            ? Icons.skip_next
            : e.ok
            ? Icons.check_circle
            : Icons.cancel,
        color: e.skipped
            ? null
            : e.ok
            ? AppColors.of(context).success
            : scheme.error,
      ),
      title: Text('${e.method} ${e.name}', overflow: TextOverflow.ellipsis),
      subtitle: Text(
        e.skipped
            ? context.l10n.runSkipped
            : context.l10n.runEntrySummary(
                    '${e.status ?? '—'}',
                    e.timeMs,
                    e.passedTests,
                    e.failedTests,
                  ) +
                  (run.total > 1
                      ? ' · ${context.l10n.runIterationSuffix(e.iteration)}'
                      : ''),
      ),
      children: [
        if (e.error != null)
          ListTile(
            dense: true,
            title: Text(e.error!, style: TextStyle(color: scheme.error)),
          ),
        for (final t in e.tests)
          ListTile(
            dense: true,
            leading: Icon(
              t.passed ? Icons.check : (t.failed ? Icons.close : Icons.remove),
              size: 16,
              color: t.failed ? scheme.error : null,
            ),
            title: Text(t.name),
            subtitle: t.message == null ? null : Text(t.message!),
          ),
      ],
    );
  }

  Widget _summary(BuildContext context, RunReport r) => Material(
    elevation: 2,
    child: Padding(
      padding: const EdgeInsets.all(8),
      child: Wrap(
        spacing: 8,
        runSpacing: 4,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          Text(
            context.l10n.runSummary(
                  r.requests,
                  r.passedTests,
                  r.failedTests,
                  r.errors,
                ) +
                (r.stoppedEarly ? ' · ${context.l10n.runStoppedEarly}' : ''),
            key: const Key('run-summary'),
          ),
          for (final (kind, label) in const [
            ('json', 'JSON'),
            ('junit', 'JUnit'),
            ('html', 'HTML'),
          ])
            OutlinedButton(
              key: Key('export-$kind'),
              onPressed: () => _export(r, kind),
              child: Text(label),
            ),
        ],
      ),
    ),
  );
}
