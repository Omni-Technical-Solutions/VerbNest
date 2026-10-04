import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:postit_core/postit_core.dart';

import '../state/editor_state.dart';
import '../state/session.dart';

/// Lists the saved versions of a request and restores one (FR-WS-008).
Future<void> showRevisions(
  BuildContext context,
  WidgetRef ref,
  String requestId,
) async {
  // Save pending edits first so the newest version is in the list.
  ref.read(editorProvider(requestId).notifier).flush();
  final repo = ref.read(repositoryProvider);
  final revs = repo.revisions(requestId);
  final rev = await showDialog<int>(
    context: context,
    builder: (_) => AlertDialog(
      title: const Text('Earlier versions'),
      content: SizedBox(
        width: 420,
        height: 320,
        child: revs.isEmpty
            ? const Center(child: Text('No earlier versions yet'))
            : ListView(
                children: [
                  for (final r in revs)
                    ListTile(
                      key: Key('rev-${r.rev}'),
                      dense: true,
                      title: Text(_when(r.savedAt)),
                      subtitle: Text(_summary(repo.revision(requestId, r.rev))),
                      trailing: const Text('Restore'),
                      onTap: () => Navigator.pop(context, r.rev),
                    ),
                ],
              ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Close'),
        ),
      ],
    ),
  );
  if (rev == null) return;
  repo.restoreRevision(requestId, rev);
  // The open editor holds a draft; drop it so it reloads the restored data.
  ref.invalidate(editorProvider(requestId));
}

String _when(DateTime t) {
  String two(int n) => n.toString().padLeft(2, '0');
  return '${t.year}-${two(t.month)}-${two(t.day)} '
      '${two(t.hour)}:${two(t.minute)}:${two(t.second)}';
}

String _summary(HttpRequestItem item) =>
    '${item.method} ${item.url}'.trim().isEmpty
    ? ''
    : '${item.method} ${item.url}';
