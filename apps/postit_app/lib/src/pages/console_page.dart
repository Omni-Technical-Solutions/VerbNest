import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../state/console_log.dart';
import '../widgets/response_view.dart';
import '../../l10n/l10n.dart';

/// Requests sent in this session with the exact heads, newest first
/// (FR-HIS-004). Secrets are masked.
class ConsolePage extends ConsumerWidget {
  const ConsolePage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final entries = ref.watch(consoleLogProvider);
    return Scaffold(
      appBar: AppBar(
        title: Text(context.l10n.consoleTitle),
        actions: [
          TextButton(
            key: const Key('console-clear'),
            onPressed: entries.isEmpty
                ? null
                : ref.read(consoleLogProvider.notifier).clear,
            child: Text(context.l10n.clear),
          ),
        ],
      ),
      body: entries.isEmpty
          ? Center(child: Text(context.l10n.consoleEmpty))
          : ListView.builder(
              itemCount: entries.length,
              itemBuilder: (context, i) => _entry(context, entries[i]),
            ),
    );
  }

  Widget _entry(BuildContext context, ConsoleEntry e) {
    final failed = e.error != null;
    String two(int n) => n.toString().padLeft(2, '0');
    final t = e.at;
    return ExpansionTile(
      dense: true,
      leading: Text(
        failed ? context.l10n.histError : '${e.status}',
        style: TextStyle(
          fontWeight: FontWeight.bold,
          color: failed ? Colors.red.shade700 : statusColor(e.status ?? 0),
        ),
      ),
      title: Text('${e.method} ${e.url}', overflow: TextOverflow.ellipsis),
      subtitle: Text(
        '${two(t.hour)}:${two(t.minute)}:${two(t.second)}'
        '${e.ms == null ? '' : ' · ${e.ms} ms'}',
      ),
      childrenPadding: const EdgeInsets.all(12),
      expandedCrossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          context.l10n.consoleSent,
          style: const TextStyle(fontWeight: FontWeight.bold),
        ),
        SelectableText(
          e.sentHead.trimRight(),
          style: const TextStyle(fontFamily: 'monospace', fontSize: 12),
        ),
        const SizedBox(height: 8),
        Text(
          failed ? context.l10n.consoleError : context.l10n.consoleReceived,
          style: const TextStyle(fontWeight: FontWeight.bold),
        ),
        SelectableText(
          e.error ?? e.responseHead ?? '',
          style: const TextStyle(fontFamily: 'monospace', fontSize: 12),
        ),
      ],
    );
  }
}
