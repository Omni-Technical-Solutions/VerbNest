import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:postit_storage/postit_storage.dart';

import 'package:postit_import/postit_import.dart';

import '../state/file_port.dart';
import '../state/folder_port.dart';
import '../state/session.dart';
import '../widgets/name_dialog.dart';
import '../workspace_host.dart';
import '../../l10n/l10n.dart';

/// Switch, create, import and export workspaces (FR-WS-002..007).
Future<void> showWorkspaces(BuildContext context, WidgetRef ref) {
  return showDialog<void>(
    context: context,
    builder: (_) => UncontrolledProviderScope(
      container: ProviderScope.containerOf(context),
      child: const _WorkspacesDialog(),
    ),
  );
}

class _WorkspacesDialog extends ConsumerWidget {
  const _WorkspacesDialog();

  Future<void> _guard(
    BuildContext context,
    Future<void> Function() action,
  ) async {
    final messenger = ScaffoldMessenger.of(context);
    final nav = Navigator.of(context);
    try {
      await action();
      nav.pop();
    } on StorageError catch (e) {
      messenger.showSnackBar(SnackBar(content: Text(e.message)));
    } on Object catch (e) {
      messenger.showSnackBar(SnackBar(content: Text('$e')));
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final session = ref.watch(sessionProvider);
    final switcher = ref.read(workspaceSwitcherProvider);
    final port = ref.read(filePortProvider);
    final currentId = session.repo.workspaceId;
    final recent = switcher.recent();

    return AlertDialog(
      title: Text(context.l10n.wsTitle),
      content: SizedBox(
        width: 440,
        height: 360,
        child: ListView(
          children: [
            ListTile(
              key: const Key('ws-current'),
              leading: const Icon(Icons.check_circle_outline),
              title: Text(session.repo.name),
              subtitle: Text(session.db.path ?? context.l10n.wsInMemory),
              trailing: IconButton(
                key: const Key('ws-rename'),
                tooltip: context.l10n.wsRename,
                icon: const Icon(Icons.edit, size: 18),
                onPressed: () async {
                  final name = await askName(
                    context,
                    title: context.l10n.wsRenameTitle,
                    initial: session.repo.name,
                    action: context.l10n.wsRename,
                  );
                  if (name == null || name.trim().isEmpty) return;
                  session.repo.name = name.trim();
                  session.local.touchWorkspace(
                    currentId,
                    name.trim(),
                    session.db.path!,
                  );
                  if (context.mounted) Navigator.pop(context);
                },
              ),
            ),
            const Divider(),
            for (final w in recent)
              if (w.id != currentId)
                ListTile(
                  key: Key('ws-${w.id}'),
                  dense: true,
                  leading: const Icon(Icons.folder_outlined),
                  title: Text(w.name),
                  subtitle: Text(w.dbPath, overflow: TextOverflow.ellipsis),
                  onTap: () => _guard(context, () => switcher.open(w.dbPath)),
                ),
          ],
        ),
      ),
      actions: [
        TextButton(
          key: const Key('ws-import'),
          onPressed: () => _guard(context, () async {
            final f = await port.pick();
            if (f != null) await switcher.importBytes(f.name, f.bytes);
          }),
          child: Text(context.l10n.wsImport),
        ),
        if (ref.read(folderPortProvider).available) ...[
          TextButton(
            key: const Key('ws-snapshot-import'),
            onPressed: () async {
              final messenger = ScaffoldMessenger.of(context);
              final nav = Navigator.of(context);
              final l10n = context.l10n;
              try {
                final files = await ref.read(folderPortProvider).read();
                if (files == null) return;
                final r = importSnapshot(session.repo, files);
                nav.pop();
                messenger.showSnackBar(
                  SnackBar(
                    content: Text(
                      l10n.wsSnapshotMerged(r.requests, r.environments) +
                          (r.conflicts.isEmpty
                              ? ''
                              : l10n.wsSnapshotKept(
                                  r.conflicts.length,
                                  r.conflicts.first,
                                )),
                    ),
                  ),
                );
              } on Object catch (e) {
                messenger.showSnackBar(SnackBar(content: Text('$e')));
              }
            },
            child: Text(context.l10n.wsImportSnapshot),
          ),
          TextButton(
            key: const Key('ws-snapshot-export'),
            onPressed: () => _guard(context, () async {
              await ref
                  .read(folderPortProvider)
                  .write(exportSnapshot(session.repo));
            }),
            child: Text(context.l10n.wsExportSnapshot),
          ),
        ],
        TextButton(
          key: const Key('ws-export'),
          onPressed: () => _guard(context, () async {
            final bytes = await switcher.exportCurrent();
            await port.save('${session.repo.name}.postit', bytes);
          }),
          child: Text(context.l10n.wsExport),
        ),
        FilledButton(
          key: const Key('ws-new'),
          onPressed: () async {
            final name = await askName(
              context,
              title: context.l10n.wsNewTitle,
              action: context.l10n.wsCreate,
            );
            if (name == null || !context.mounted) return;
            await _guard(context, () => switcher.create(name));
          },
          child: Text(context.l10n.wsNew),
        ),
      ],
    );
  }
}
