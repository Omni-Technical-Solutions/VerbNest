import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../state/console_log.dart';
import '../widgets/response_view.dart';

/// Requests sent in this session with the exact heads, newest first
/// (FR-HIS-004). Secrets are masked.
class ConsolePage extends ConsumerWidget {
  const ConsolePage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final entries = ref.watch(consoleLogProvider);
    return Scaffold(
      appBar: AppBar(
        title: const Text('Network console'),
        actions: [
          TextButton(
            key: const Key('console-clear'),
            onPressed: entries.isEmpty
                ? null
                : ref.read(consoleLogProvider.notifier).clear,
            child: const Text('Clear'),
          ),
        ],
      ),
      body: entries.isEmpty
          ? const Center(child: Text('Nothing sent in this session yet'))
          : ListView.builder(
              itemCount: entries.length,
              itemBuilder: (context, i) => _entry(entries[i]),
            ),
    );
  }

  Widget _entry(ConsoleEntry e) {
    final failed = e.error != null;
    String two(int n) => n.toString().padLeft(2, '0');
    final t = e.at;
    return ExpansionTile(
      dense: true,
      leading: Text(
        failed ? 'ERR' : '${e.status}',
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
        const Text('Sent', style: TextStyle(fontWeight: FontWeight.bold)),
        SelectableText(
          e.sentHead.trimRight(),
          style: const TextStyle(fontFamily: 'monospace', fontSize: 12),
        ),
        const SizedBox(height: 8),
        Text(
          failed ? 'Error' : 'Received',
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
