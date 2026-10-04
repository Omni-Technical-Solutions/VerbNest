import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart' hide DataRow;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:postit_core/postit_core.dart';

import '../state/file_port.dart';
import '../state/runner.dart';
import '../state/session.dart';

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
        _dataError = rows.isEmpty ? 'The file has no rows' : null;
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
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('Report saved')));
    }
  }

  @override
  Widget build(BuildContext context) {
    final run = ref.watch(runnerProvider);
    return Scaffold(
      appBar: AppBar(title: Text('Run "$_title"')),
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (!run.running) _setup(context),
          if (run.running) _progress(run),
          const Divider(height: 1),
          Expanded(child: _results(context, run)),
          if (run.report != null) _summary(run.report!),
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
            constraints: const BoxConstraints(maxHeight: 220),
            child: _picks.isEmpty
                ? const Center(child: Text('No requests to run here'))
                : ReorderableListView(
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
                  ),
          ),
          Wrap(
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
                  decoration: const InputDecoration(
                    labelText: 'Iterations',
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
                  decoration: const InputDecoration(
                    labelText: 'Delay (ms)',
                    isDense: true,
                  ),
                  onChanged: (v) =>
                      _delayMs = (int.tryParse(v) ?? 0).clamp(0, 600000),
                ),
              ),
              FilterChip(
                key: const Key('run-stop-on-failure'),
                label: const Text('Stop on first failure'),
                selected: _stopOnFailure,
                onSelected: (v) => setState(() => _stopOnFailure = v),
              ),
              OutlinedButton.icon(
                key: const Key('run-data'),
                onPressed: _pickData,
                icon: const Icon(Icons.table_chart_outlined),
                label: Text(
                  _dataName == null
                      ? 'Data file…'
                      : '$_dataName (${_data.length} rows)',
                ),
              ),
              if (_dataName != null)
                IconButton(
                  tooltip: 'Remove data file',
                  icon: const Icon(Icons.close, size: 18),
                  onPressed: () => setState(() {
                    _data = const [];
                    _dataName = null;
                  }),
                ),
              FilledButton.icon(
                key: const Key('run-start'),
                onPressed: _picks.any((p) => p.on) ? _start : null,
                icon: const Icon(Icons.play_arrow),
                label: const Text('Run'),
              ),
            ],
          ),
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

  Widget _progress(RunnerState run) => Padding(
    padding: const EdgeInsets.all(8),
    child: Row(
      children: [
        const SizedBox(
          width: 16,
          height: 16,
          child: CircularProgressIndicator(strokeWidth: 2),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Text(
            'Iteration ${run.iteration} of ${run.total}'
            '${run.currentName == null ? '' : ' · ${run.currentName}'}',
            key: const Key('run-progress'),
          ),
        ),
        OutlinedButton(
          key: const Key('run-stop'),
          onPressed: ref.read(runnerProvider.notifier).stop,
          child: const Text('Stop'),
        ),
      ],
    ),
  );

  Widget _results(BuildContext context, RunnerState run) {
    if (run.entries.isEmpty) {
      return const Center(child: Text('Results appear here'));
    }
    final scheme = Theme.of(context).colorScheme;
    return ListView(
      key: const Key('run-results'),
      children: [
        for (final e in run.entries)
          ExpansionTile(
            leading: Icon(
              e.skipped
                  ? Icons.skip_next
                  : e.ok
                  ? Icons.check_circle
                  : Icons.cancel,
              color: e.skipped
                  ? null
                  : e.ok
                  ? Colors.green
                  : scheme.error,
            ),
            title: Text(
              '${e.method} ${e.name}',
              overflow: TextOverflow.ellipsis,
            ),
            subtitle: Text(
              e.skipped
                  ? 'Skipped'
                  : '${e.status ?? '—'} · ${e.timeMs} ms · '
                        '${e.passedTests} passed, ${e.failedTests} failed'
                        '${run.total > 1 ? ' · iteration ${e.iteration}' : ''}',
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
                    t.passed
                        ? Icons.check
                        : (t.failed ? Icons.close : Icons.remove),
                    size: 16,
                    color: t.failed ? scheme.error : null,
                  ),
                  title: Text(t.name),
                  subtitle: t.message == null ? null : Text(t.message!),
                ),
            ],
          ),
      ],
    );
  }

  Widget _summary(RunReport r) => Material(
    elevation: 2,
    child: Padding(
      padding: const EdgeInsets.all(8),
      child: Wrap(
        spacing: 8,
        runSpacing: 4,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          Text(
            '${r.requests} requests · ${r.passedTests} passed · '
            '${r.failedTests} failed · ${r.errors} errors'
            '${r.stoppedEarly ? ' · stopped early' : ''}',
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
