import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';
import 'package:verbnest_storage/verbnest_storage.dart';

import '../../l10n/l10n.dart';
import '../pages/container_settings_page.dart';
import '../pages/revisions_dialog.dart';
import '../pages/runner_page.dart';
import '../state/import_actions.dart';
import '../state/session.dart';
import '../state/tree_state.dart';
import 'code_dialog.dart';
import 'name_dialog.dart';
import 'ui/still_route.dart';
import 'ui/toast.dart';

/// What the menu of a collection, folder or request can do.
enum SidebarAction {
  newRequest,
  newFolder,
  rename,
  settings,
  run,
  duplicate,
  moveUp,
  moveDown,
  delete,
  copyCurl,
  generateCode,
  toggleFavourite,
  versions,
  exportPostman,
}

List<PopupMenuEntry<SidebarAction>> sidebarMenuItems(
  BuildContext context,
  WidgetRef ref,
  NodeInfo node,
) => [
  if (node.isContainer) ...[
    PopupMenuItem(
      value: SidebarAction.newRequest,
      child: Text(context.l10n.sbNewRequest),
    ),
    PopupMenuItem(
      value: SidebarAction.newFolder,
      child: Text(context.l10n.sbNewFolder),
    ),
  ],
  PopupMenuItem(
    value: SidebarAction.rename,
    child: Text(context.l10n.sbRename),
  ),
  if (node.isContainer)
    PopupMenuItem(value: SidebarAction.run, child: Text(context.l10n.sbRun)),
  if (node.isContainer)
    PopupMenuItem(
      value: SidebarAction.settings,
      child: Text(context.l10n.sbSettings),
    ),
  PopupMenuItem(
    value: SidebarAction.duplicate,
    child: Text(context.l10n.sbDuplicate),
  ),
  PopupMenuItem(
    value: SidebarAction.moveUp,
    child: Text(context.l10n.sbMoveUp),
  ),
  PopupMenuItem(
    value: SidebarAction.moveDown,
    child: Text(context.l10n.sbMoveDown),
  ),
  if (!node.isContainer)
    PopupMenuItem(
      value: SidebarAction.versions,
      child: Text(context.l10n.sbVersions),
    ),
  if (!node.isContainer)
    PopupMenuItem(
      value: SidebarAction.copyCurl,
      child: Text(context.l10n.sbCopyCurl),
    ),
  if (!node.isContainer)
    PopupMenuItem(
      value: SidebarAction.toggleFavourite,
      child: Text(
        ref.read(repositoryProvider).isFavourite(node.id)
            ? context.l10n.sbFavRemove
            : context.l10n.sbFavAdd,
      ),
    ),
  if (!node.isContainer)
    PopupMenuItem(
      value: SidebarAction.generateCode,
      child: Text(context.l10n.sbGenerateCode),
    ),
  if (node.parentId == null)
    PopupMenuItem(
      value: SidebarAction.exportPostman,
      child: Text(context.l10n.sbCopyPostman),
    ),
  PopupMenuItem(
    value: SidebarAction.delete,
    child: Text(context.l10n.sbDelete),
  ),
];

/// Tells the user an item moved, with a way back.
void movedToast(BuildContext context, WidgetRef ref, String id, Undo undo) {
  final name = ref.read(repositoryProvider).node(id).name;
  showToast(
    context,
    context.l10n.toastMoved(name),
    onUndo: undo,
    undoLabel: context.l10n.undo,
  );
}

/// Does [action] on [node]. [onOpenRequest] hears about a request just
/// created; [onChanged] is called when a change should redraw the tree.
Future<void> runSidebarAction(
  BuildContext context,
  WidgetRef ref,
  SidebarAction action,
  NodeInfo node, {
  void Function(String requestId)? onOpenRequest,
  VoidCallback? onChanged,
}) async {
  final l10n = context.l10n;
  final actions = ref.read(treeActionsProvider);
  switch (action) {
    case SidebarAction.newRequest:
      final name = await askName(
        context,
        title: l10n.sbNewRequest,
        action: l10n.sbCreate,
      );
      if (name == null) return;
      final id = actions.newRequest(node.id, name: name);
      onOpenRequest?.call(id);
    case SidebarAction.newFolder:
      if (!context.mounted) return;
      final name = await askName(
        context,
        title: l10n.sbNewFolder,
        action: l10n.sbCreate,
      );
      if (name != null) actions.newFolder(node.id, name);
    case SidebarAction.rename:
      final name = await askName(
        context,
        title: l10n.sbRename,
        initial: node.name,
      );
      if (name != null) actions.rename(node.id, name);
    case SidebarAction.settings:
      await Navigator.of(context).push(
        StillPageRoute<void>(
          builder: (_) => ContainerSettingsPage(containerId: node.id),
        ),
      );
    case SidebarAction.run:
      await Navigator.of(context).push(
        StillPageRoute<void>(builder: (_) => RunnerPage(containerId: node.id)),
      );
    case SidebarAction.duplicate:
      actions.duplicate(node.id);
    case SidebarAction.moveUp:
      final undo = actions.nudge(node.id, -1);
      if (undo != null && context.mounted) {
        movedToast(context, ref, node.id, undo);
      }
    case SidebarAction.moveDown:
      final undo = actions.nudge(node.id, 1);
      if (undo != null && context.mounted) {
        movedToast(context, ref, node.id, undo);
      }
    case SidebarAction.versions:
      await showRevisions(context, ref, node.id);
    case SidebarAction.copyCurl:
      await _copy(
        context,
        requestAsCurl(ref.read(sessionProvider), node.id),
        l10n.sbCurlCopied,
      );
    case SidebarAction.toggleFavourite:
      final repo = ref.read(repositoryProvider);
      repo.setFavourite(node.id, !repo.isFavourite(node.id));
      onChanged?.call();
    case SidebarAction.generateCode:
      await showDialog<void>(
        animationStyle: AnimationStyle.noAnimation,
        context: context,
        builder: (_) => CodeDialog(requestId: node.id),
      );
    case SidebarAction.exportPostman:
      await _copy(
        context,
        exportCollectionJson(ref.read(sessionProvider), node.id),
        l10n.sbPostmanCopied,
      );
    case SidebarAction.delete:
      final ok = await confirm(
        context,
        title: l10n.sbDeleteTitle(node.name),
        message: node.isContainer ? l10n.sbDeleteFolderMsg : l10n.sbDeleteMsg,
      );
      if (!ok) return;
      final undo = actions.deleteUndoable(node.id);
      if (context.mounted) {
        showToast(
          context,
          l10n.toastDeleted(node.name),
          onUndo: undo,
          undoLabel: l10n.undo,
        );
      }
  }
}

Future<void> _copy(BuildContext context, String text, String message) async {
  await Clipboard.setData(ClipboardData(text: text));
  if (!context.mounted) return;
  showToast(context, message);
}
