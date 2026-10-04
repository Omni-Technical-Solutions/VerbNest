import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:postit_storage/postit_storage.dart';

import '../state/session.dart';
import '../state/variables.dart';
import '../widgets/name_dialog.dart';
import '../widgets/response_view.dart';

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
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.all(8),
          child: Row(
            children: [
              Expanded(
                child: TextField(
                  key: const Key('history-search'),
                  decoration: const InputDecoration(
                    isDense: true,
                    prefixIcon: Icon(Icons.search, size: 18),
                    hintText: 'Search method, URL or status',
                  ),
                  onChanged: (v) => setState(() => _query = v.trim()),
                ),
              ),
              IconButton(
                key: const Key('history-clear'),
                tooltip: 'Clear history',
                icon: const Icon(Icons.delete_sweep_outlined),
                onPressed: entries.isEmpty ? null : () => _clear(session),
              ),
            ],
          ),
        ),
        Expanded(
          child: entries.isEmpty
              ? Center(
                  child: Text(
                    _query.isEmpty
                        ? 'Requests you send appear here'
                        : 'Nothing matches "$_query"',
                  ),
                )
              : ListView.builder(
                  itemCount: entries.length,
                  itemBuilder: (context, i) => _tile(entries[i]),
                ),
        ),
      ],
    );
  }

  Future<void> _clear(WorkspaceSession session) async {
    final ok = await confirm(
      context,
      title: 'Clear history?',
      message: 'All stored requests and responses on this device are removed.',
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
          failed ? 'ERR' : '${e.status}',
          style: TextStyle(
            fontWeight: FontWeight.bold,
            color: failed ? Colors.red.shade700 : statusColor(e.status ?? 0),
          ),
        ),
      ),
      title: Text('${e.method} ${e.url}', overflow: TextOverflow.ellipsis),
      subtitle: Text(
        [
          e.sentAt.toLocal().toString().split('.').first,
          if (e.totalMs != null) '${e.totalMs} ms',
          if (e.environmentName != null) e.environmentName!,
        ].join(' · '),
      ),
      onTap: () => Navigator.of(context).push(
        MaterialPageRoute<void>(builder: (_) => HistoryDetailPage(entry: e)),
      ),
    );
  }
}

class HistoryDetailPage extends StatelessWidget {
  const HistoryDetailPage({super.key, required this.entry});

  final HistoryEntry entry;

  @override
  Widget build(BuildContext context) {
    final request = const JsonEncoder.withIndent('  ')
        .convert(jsonDecode(entry.requestJson));
    final body = entry.responseBody;
    return DefaultTabController(
      length: 2,
      child: Scaffold(
        appBar: AppBar(
          title: Text(
            '${entry.method} ${entry.url}',
            overflow: TextOverflow.ellipsis,
          ),
          bottom: const TabBar(
            tabs: [
              Tab(text: 'Request'),
              Tab(text: 'Response'),
            ],
          ),
        ),
        body: TabBarView(
          children: [
            _text(request),
            _text(
              entry.error ??
                  (body == null
                      ? 'No response body stored'
                      : utf8.decode(body, allowMalformed: true) +
                            (entry.bodyTruncated
                                ? '\n\n[truncated when stored]'
                                : '')),
            ),
          ],
        ),
      ),
    );
  }

  Widget _text(String t) => SingleChildScrollView(
    padding: const EdgeInsets.all(12),
    child: SelectableText(
      t,
      style: const TextStyle(fontFamily: 'monospace', fontSize: 13),
    ),
  );
}
