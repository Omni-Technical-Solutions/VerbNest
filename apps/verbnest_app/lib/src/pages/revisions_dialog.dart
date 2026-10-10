import 'package:material_ui/material_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:verbnest_core/verbnest_core.dart';

import '../state/editor_state.dart';
import '../state/session.dart';
import '../../l10n/l10n.dart';

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
      title: Text(context.l10n.revisionsTitle),
      content: SizedBox(
        width: 420,
        height: 320,
        child: revs.isEmpty
            ? Center(child: Text(context.l10n.revisionsNone))
            : ListView(
                children: [
                  for (final r in revs)
                    ListTile(
                      key: Key('rev-${r.rev}'),
                      dense: true,
                      title: Text(_when(r.savedAt)),
                      subtitle: Text(_summary(repo.revision(requestId, r.rev))),
                      trailing: Text(context.l10n.restore),
                      onTap: () => Navigator.pop(context, r.rev),
                    ),
                ],
              ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: Text(context.l10n.close),
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
