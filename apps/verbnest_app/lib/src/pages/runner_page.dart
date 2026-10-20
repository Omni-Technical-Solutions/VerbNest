import 'dart:convert';

import '../widgets/ui/still_controls.dart';

import 'dart:typed_data';

import 'package:material_ui/material_ui.dart' hide DataRow;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:verbnest_core/verbnest_core.dart';

import '../state/file_port.dart';
import '../state/runner.dart';
import '../state/session.dart';
import '../widgets/mock_server_dialog.dart';
import 'runner_parts.dart';
import '../../l10n/l10n.dart';
import '../layout_class.dart';
import '../widgets/ui/toast.dart';
import '../widgets/ui/ui.dart';
import '../widgets/ui/still_tooltip.dart';

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
              animationStyle: AnimationStyle.noAnimation,
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
          if (run.running)
            RunProgress(
              run: run,
              onStop: ref.read(runnerProvider.notifier).stop,
            ),
          const Divider(height: 1),
          Expanded(child: RunResults(run: run)),
          if (run.report != null)
            RunSummary(report: run.report!, onExport: _export),
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
          StillCheckboxListTile(
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
        StillChip(
          showCheckmark: true,
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
          StillIconButton(
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
}
