import 'dart:convert';

import '../widgets/ui/still_route.dart';
import '../widgets/ui/still_tabs.dart';

import 'package:material_ui/material_ui.dart';

import '../theme.dart';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:verbnest_http/verbnest_http.dart' show Masker;
import 'package:verbnest_storage/verbnest_storage.dart';

import '../state/history_actions.dart';
import 'console_page.dart';
import '../state/session.dart';
import '../state/tree_state.dart';
import '../state/variables.dart';
import '../widgets/name_dialog.dart';
import '../widgets/response_view.dart';
import '../../l10n/l10n.dart';
import '../widgets/ui/ui.dart';

/// Sent requests, newest first, with search (FR-HIS-001/002).
class HistoryPage extends ConsumerStatefulWidget {
  const HistoryPage({super.key});

  @override
  ConsumerState<HistoryPage> createState() => _HistoryPageState();
}

class _HistoryPageState extends ConsumerState<HistoryPage> {
  String _query = '';

  @override
  Widget build(BuildContext context) {
    ref.watch(historyTickProvider);
    final session = ref.watch(sessionProvider);
    final entries = session.local.listHistory(
      session.repo.workspaceId,
      query: _query,
    );
    // A list this wide is hard to scan; keep it a readable column.
    return Align(
      alignment: Alignment.topCenter,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 960),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _toolbar(session, entries.isEmpty),
            Expanded(
              child: entries.isEmpty
                  ? EmptyState(
                      icon: _query.isEmpty ? Icons.history : Icons.search_off,
                      title: _query.isEmpty
                          ? context.l10n.histEmpty
                          : context.l10n.histNoMatch(_query),
                    )
                  : _grouped(entries),
            ),
          ],
        ),
      ),
    );
  }

  Widget _toolbar(WorkspaceSession session, bool empty) {
    return Padding(
      padding: const EdgeInsets.all(8),
      child: Row(
        children: [
          Expanded(
            child: TextField(
              key: const Key('history-search'),
              decoration: InputDecoration(
                isDense: true,
                prefixIcon: const Icon(Icons.search, size: 18),
                hintText: context.l10n.histSearchHint,
              ),
              onChanged: (v) => setState(() => _query = v.trim()),
            ),
          ),
          IconButton(
            key: const Key('console-open'),
            tooltip: context.l10n.histConsole,
            icon: const Icon(Icons.terminal),
            onPressed: () => Navigator.of(
              context,
            ).push(StillPageRoute<void>(builder: (_) => const ConsolePage())),
          ),
          IconButton(
            key: const Key('history-clear'),
            tooltip: context.l10n.histClear,
            icon: const Icon(Icons.delete_sweep_outlined),
            onPressed: empty ? null : () => _clear(session),
          ),
        ],
      ),
    );
  }

  Widget _grouped(List<HistoryEntry> entries) {
    final now = DateTime.now();
    final items = <Object>[];
    String? last;
    for (final e in entries) {
      final label = dayLabel(e.sentAt, now);
      if (label != last) items.add(label);
      last = label;
      items.add(e);
    }
    return ListView.builder(
      itemCount: items.length,
      itemBuilder: (context, i) {
        final item = items[i];
        if (item is String) {
          return Padding(
            key: Key('history-day-$item'),
            padding: const EdgeInsetsDirectional.fromSTEB(16, 12, 16, 4),
            child: Text(switch (item) {
              'Today' => context.l10n.today,
              'Yesterday' => context.l10n.yesterday,
              _ => item,
            }, style: Theme.of(context).textTheme.labelLarge),
          );
        }
        return _tile(item as HistoryEntry);
      },
    );
  }

  Future<void> _clear(WorkspaceSession session) async {
    final ok = await confirm(
      context,
      title: context.l10n.histClearTitle,
      message: context.l10n.histClearMessage,
    );
    if (!ok) return;
    session.local.clearHistory(session.repo.workspaceId);
    ref.read(historyTickProvider.notifier).bump();
  }

  Widget _tile(HistoryEntry e) {
    final failed = e.error != null;
    return ListTile(
      key: Key('history-${e.id}'),
      dense: true,
      leading: SizedBox(
        width: 44,
        child: Text(
          failed ? context.l10n.histError : '${e.status}',
          style: TextStyle(
            fontWeight: FontWeight.bold,
            color: failed
                ? AppColors.of(context).danger
                : statusColor(context, e.status ?? 0),
          ),
        ),
      ),
      title: Row(
        children: [
          MethodBadge(e.method, width: 48),
          Expanded(child: Text(e.url, overflow: TextOverflow.ellipsis)),
        ],
      ),
      subtitle: Text(
        [
          e.sentAt.toLocal().toString().split('.').first,
          if (e.totalMs != null) '${e.totalMs} ms',
          if (e.environmentName != null) e.environmentName!,
        ].join(' · '),
      ),
      onTap: () => Navigator.of(
        context,
      ).push(StillPageRoute<void>(builder: (_) => HistoryDetailPage(entry: e))),
    );
  }
}

class HistoryDetailPage extends ConsumerWidget {
  const HistoryDetailPage({super.key, required this.entry});

  final HistoryEntry entry;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final session = ref.watch(sessionProvider);
    final exists = requestStillExists(session, entry);
    final request = const JsonEncoder.withIndent('  ')
        .convert(jsonDecode(entry.requestJson));
    return DefaultTabController(
      animationDuration: Duration.zero,
      length: 2,
      child: Scaffold(
        appBar: AppBar(
          title: Text(
            '${entry.method} ${entry.url}',
            overflow: TextOverflow.ellipsis,
          ),
          actions: _actions(context, ref, session, exists),
          bottom: StillTabBar(
            tabs: [
              Tab(text: context.l10n.histTabRequest),
              Tab(text: context.l10n.histTabResponse),
            ],
          ),
        ),
        body: TabBarView(
          children: [
            _text(request),
            _text(entry.error ?? _responseText(context)),
          ],
        ),
      ),
    );
  }

  String _responseText(BuildContext context) {
    final body = entry.responseBody;
    if (body == null) return context.l10n.histNoBody;
    final truncated = entry.bodyTruncated
        ? '\n\n${context.l10n.histTruncated}'
        : '';
    return utf8.decode(body, allowMalformed: true) + truncated;
  }

  List<Widget> _actions(
    BuildContext context,
    WidgetRef ref,
    WorkspaceSession session,
    bool exists,
  ) {
    return [
      if (exists)
        TextButton(
          key: const Key('history-open'),
          onPressed: () {
            ref.read(tabsProvider.notifier).open(entry.requestId!);
            Navigator.of(context).popUntil((r) => r.isFirst);
          },
          child: Text(context.l10n.histOpenRequest),
        ),
      TextButton(
        key: const Key('history-save'),
        onPressed: () => _saveAsNew(context, ref, session),
        child: Text(context.l10n.histSaveAsNew),
      ),
    ];
  }

  void _saveAsNew(
    BuildContext context,
    WidgetRef ref,
    WorkspaceSession session,
  ) {
    final masked = requestFromHistory(entry).hadMasked;
    final id = saveHistoryAsRequest(session, entry);
    ref.read(tabsProvider.notifier).open(id);
    ScaffoldMessenger.of(context).showSnackBar(
      snackBarAnimationStyle: AnimationStyle.noAnimation,
      SnackBar(
        content: Text(
          masked
              ? context.l10n.histSavedMasked(Masker.placeholder)
              : context.l10n.histSaved,
        ),
      ),
    );
  }

  Widget _text(String t) => SingleChildScrollView(
    padding: const EdgeInsets.all(12),
    child: SelectableText(t, style: monoStyle(fontSize: 13)),
  );
}

/// "Today", "Yesterday" or the date, for grouping history (FR-HIS-002).
String dayLabel(DateTime t, DateTime now) {
  final local = t.toLocal();
  final day = DateTime(local.year, local.month, local.day);
  final today = DateTime(now.year, now.month, now.day);
  final diff = today.difference(day).inDays;
  if (diff == 0) return 'Today';
  if (diff == 1) return 'Yesterday';
  String two(int n) => n.toString().padLeft(2, '0');
  return '${day.year}-${two(day.month)}-${two(day.day)}';
}
