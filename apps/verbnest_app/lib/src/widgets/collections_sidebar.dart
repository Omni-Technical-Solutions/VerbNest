import 'dart:async';

import 'package:material_ui/material_ui.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:verbnest_storage/verbnest_storage.dart';

import '../pages/container_settings_page.dart';
import '../pages/runner_page.dart';
import '../pages/revisions_dialog.dart';
import '../pages/search_dialog.dart';
import '../pages/workspaces_dialog.dart';
import '../workspace_host.dart';
import '../state/import_actions.dart';
import '../state/session.dart';
import '../state/sidebar_rows.dart';
import '../state/tree_state.dart';
import '../theme.dart';
import 'code_dialog.dart';
import 'ui/ui.dart';
import 'name_dialog.dart';
import '../../l10n/l10n.dart';
import 'ui/toast.dart';

enum _Action {
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

/// The collections tree with filter and per-item actions (FR-COL-001/003).
///
/// Reorder by long-press drag and drop, or with the move up/down menu items
/// (keyboard and assistive technology). Dropping on a folder or collection
/// moves the item into it; dropping on a request places the item before it.
class CollectionsSidebar extends ConsumerStatefulWidget {
  const CollectionsSidebar({super.key, this.onOpenRequest});

  /// Called after a request is chosen; compact layouts use it to navigate.
  final void Function(String requestId)? onOpenRequest;

  @override
  ConsumerState<CollectionsSidebar> createState() => _CollectionsSidebarState();
}

class _CollectionsSidebarState extends ConsumerState<CollectionsSidebar> {
  bool _favOnly = false;
  String _filter = '';

  @override
  Widget build(BuildContext context) {
    ref.watch(workspaceVersionProvider);
    final repo = ref.watch(repositoryProvider);
    final expanded = ref.watch(expandedProvider);
    final rows = sidebarRows(repo.children, expanded, _filter);
    final active = ref.watch(tabsProvider).active;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _header(context),
        Expanded(
          child: _favOnly
              ? _favourites(context, active)
              : rows.isEmpty
              ? _empty(context)
              : ListView.builder(
                  itemCount: rows.length,
                  itemBuilder: (context, i) => _tile(context, rows[i], active),
                ),
        ),
      ],
    );
  }

  /// Workspace switching needs the host from `main`; widget tests that
  /// mount the sidebar alone do not have one.
  bool _hasHost(BuildContext context) {
    try {
      ref.read(workspaceSwitcherProvider);
      return true;
    } catch (_) {
      return false;
    }
  }

  Widget _header(BuildContext context) {
    return Padding(
      padding: const EdgeInsetsDirectional.fromSTEB(12, 8, 4, 4),
      child: Row(
        children: [
          Expanded(
            child: TextField(
              key: const Key('sidebar-filter'),
              decoration: InputDecoration(
                isDense: true,
                prefixIcon: const Icon(Icons.search, size: 18),
                hintText: context.l10n.sbFilter,
              ),
              onChanged: (v) => setState(() => _filter = v),
            ),
          ),
          IconButton(
            key: const Key('favourites-filter'),
            tooltip: _favOnly ? context.l10n.sbShowAll : context.l10n.sbShowFav,
            icon: Icon(_favOnly ? Icons.star : Icons.star_border),
            onPressed: () => setState(() => _favOnly = !_favOnly),
          ),
          PopupMenuButton<String>(
            key: const Key('sidebar-more'),
            icon: const Icon(Icons.more_horiz),
            onSelected: (v) async {
              switch (v) {
                case 'search':
                  final hit = await runSearch(context, ref);
                  if (hit != null && hit.kind == NodeKind.request) {
                    widget.onOpenRequest?.call(hit.id);
                  }
                case 'import':
                  _import(context);
                case 'workspaces':
                  showWorkspaces(context, ref);
              }
            },
            itemBuilder: (_) => [
              PopupMenuItem(
                key: const Key('search'),
                value: 'search',
                child: Text(context.l10n.sbSearch),
              ),
              PopupMenuItem(
                key: const Key('import'),
                value: 'import',
                child: Text(context.l10n.sbImport),
              ),
              if (_hasHost(context))
                PopupMenuItem(
                  key: const Key('workspaces'),
                  value: 'workspaces',
                  child: Text(context.l10n.sbWorkspaces),
                ),
            ],
          ),
          IconButton(
            key: const Key('new-collection'),
            tooltip: context.l10n.sbNewCollection,
            icon: const Icon(Icons.create_new_folder_outlined),
            onPressed: () => _newCollection(context),
          ),
        ],
      ),
    );
  }

  Widget _favourites(BuildContext context, String? active) {
    final repo = ref.read(repositoryProvider);
    final ids = repo.favourites();
    if (ids.isEmpty) {
      return EmptyState(
        key: const Key('no-favourites'),
        icon: Icons.star_border,
        title: context.l10n.sbNoFav,
      );
    }
    return ListView(
      children: [
        for (final id in ids)
          _tileBody(context, SidebarRow(repo.node(id), 0), active),
      ],
    );
  }

  Widget _empty(BuildContext context) {
    final filtering = _filter.trim().isNotEmpty;
    return EmptyState(
      icon: filtering ? Icons.search_off : Icons.folder_open_outlined,
      title: filtering
          ? context.l10n.sbNoMatch(_filter)
          : context.l10n.sbNoCollections,
    );
  }

  Widget _tile(BuildContext context, SidebarRow row, String? active) {
    final node = row.node;
    final tile = _tileBody(context, row, active);
    // Long press starts a drag so scrolling and taps keep working on touch.
    return DragTarget<String>(
      key: Key('drop-${node.id}'),
      onWillAcceptWithDetails: (d) =>
          ref.read(treeActionsProvider).canDrop(d.data, node.id),
      onAcceptWithDetails: (d) {
        try {
          final undo = ref.read(treeActionsProvider).drop(d.data, node.id);
          if (undo != null) _movedToast(context, d.data, undo);
        } on StorageError catch (e) {
          showToast(context, e.message);
        }
      },
      builder: (context, candidates, _) => LongPressDraggable<String>(
        key: Key('drag-${node.id}'),
        data: node.id,
        delay: const Duration(milliseconds: 250),
        feedback: Material(
          elevation: 4,
          child: SizedBox(
            width: 220,
            child: ListTile(dense: true, title: Text(node.name)),
          ),
        ),
        childWhenDragging: Opacity(opacity: 0.4, child: tile),
        child: DecoratedBox(
          decoration: BoxDecoration(
            border: candidates.isEmpty
                ? null
                : Border(
                    top: BorderSide(
                      color: Theme.of(context).colorScheme.primary,
                      width: 2,
                    ),
                  ),
          ),
          child: tile,
        ),
      ),
    );
  }

  Widget _tileBody(BuildContext context, SidebarRow row, String? active) {
    final node = row.node;
    final selected = node.id == active;
    return GestureDetector(
      behavior: HitTestBehavior.translucent,
      // A pointer shortcut only. Its actions are all in the row's labelled
      // menu, and it would otherwise show up as an unlabelled button.
      excludeFromSemantics: true,
      onSecondaryTapUp: (d) => _contextMenu(context, node, d.globalPosition),
      child: _rowTile(context, row, selected),
    );
  }

  Widget _rowTile(BuildContext context, SidebarRow row, bool selected) {
    final node = row.node;
    return ListTile(
      key: Key('node-${node.id}'),
      dense: true,
      selected: selected,
      contentPadding: EdgeInsetsDirectional.only(
        start: 12.0 + row.depth * 16,
        end: 0,
      ),
      leading: _leading(node, row.expanded),
      title: Row(
        children: [
          Flexible(child: Text(node.name, overflow: TextOverflow.ellipsis)),
          if (!node.isContainer &&
              ref.read(repositoryProvider).isFavourite(node.id))
            Padding(
              padding: const EdgeInsetsDirectional.only(start: 4),
              child: Icon(
                Icons.star,
                key: Key('fav-${node.id}'),
                size: 12,
                color: AppColors.of(context).favourite,
              ),
            ),
        ],
      ),
      trailing: _menu(context, node),
      onTap: () => _onTap(node),
    );
  }

  Widget _leading(NodeInfo node, bool expanded) {
    if (node.isContainer) {
      return Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          AnimatedRotation(
            turns: expanded ? 0.25 : 0,
            duration: Motion.of(context, Motion.fast),
            curve: Motion.curve,
            child: const Icon(Icons.chevron_right, size: 16),
          ),
          Icon(expanded ? Icons.folder_open : Icons.folder_outlined, size: 20),
        ],
      );
    }
    return MethodBadge(node.method ?? 'GET');
  }

  void _onTap(NodeInfo node) {
    if (node.isContainer) {
      ref.read(expandedProvider.notifier).toggle(node.id);
      return;
    }
    // A single click previews; a second click on the same row soon after pins
    // the tab. A timer, not a clock, marks "soon" so it follows test time too.
    final again = _lastTapId == node.id;
    _lastTapId = node.id;
    _tapWindow?.cancel();
    _tapWindow = Timer(
      const Duration(milliseconds: 400),
      () => _lastTapId = null,
    );
    ref.read(tabsProvider.notifier)
      ..open(node.id, preview: true)
      ..pin(again ? node.id : '');
    widget.onOpenRequest?.call(node.id);
  }

  String? _lastTapId;
  Timer? _tapWindow;

  @override
  void dispose() {
    _tapWindow?.cancel();
    super.dispose();
  }

  Widget _menu(BuildContext context, NodeInfo node) {
    return PopupMenuButton<_Action>(
      key: Key('menu-${node.id}'),
      tooltip: context.l10n.sbActions,
      icon: const Icon(Icons.more_vert, size: 18),
      onSelected: (a) => _run(context, a, node),
      itemBuilder: (_) => _items(context, node),
    );
  }

  /// Same actions as the row's menu button, opened by right-click.
  Future<void> _contextMenu(
    BuildContext context,
    NodeInfo node,
    Offset position,
  ) async {
    final overlay =
        Overlay.of(context).context.findRenderObject()! as RenderBox;
    final action = await showMenu<_Action>(
      context: context,
      position: RelativeRect.fromRect(
        position & const Size(1, 1),
        Offset.zero & overlay.size,
      ),
      items: _items(context, node),
    );
    if (action != null && context.mounted) _run(context, action, node);
  }

  List<PopupMenuEntry<_Action>> _items(BuildContext context, NodeInfo node) => [
    if (node.isContainer) ...[
      PopupMenuItem(
        value: _Action.newRequest,
        child: Text(context.l10n.sbNewRequest),
      ),
      PopupMenuItem(
        value: _Action.newFolder,
        child: Text(context.l10n.sbNewFolder),
      ),
    ],
    PopupMenuItem(value: _Action.rename, child: Text(context.l10n.sbRename)),
    if (node.isContainer)
      PopupMenuItem(value: _Action.run, child: Text(context.l10n.sbRun)),
    if (node.isContainer)
      PopupMenuItem(
        value: _Action.settings,
        child: Text(context.l10n.sbSettings),
      ),
    PopupMenuItem(
      value: _Action.duplicate,
      child: Text(context.l10n.sbDuplicate),
    ),
    PopupMenuItem(value: _Action.moveUp, child: Text(context.l10n.sbMoveUp)),
    PopupMenuItem(
      value: _Action.moveDown,
      child: Text(context.l10n.sbMoveDown),
    ),
    if (!node.isContainer)
      PopupMenuItem(
        value: _Action.versions,
        child: Text(context.l10n.sbVersions),
      ),
    if (!node.isContainer)
      PopupMenuItem(
        value: _Action.copyCurl,
        child: Text(context.l10n.sbCopyCurl),
      ),
    if (!node.isContainer)
      PopupMenuItem(
        value: _Action.toggleFavourite,
        child: Text(
          ref.read(repositoryProvider).isFavourite(node.id)
              ? context.l10n.sbFavRemove
              : context.l10n.sbFavAdd,
        ),
      ),
    if (!node.isContainer)
      PopupMenuItem(
        value: _Action.generateCode,
        child: Text(context.l10n.sbGenerateCode),
      ),
    if (node.parentId == null)
      PopupMenuItem(
        value: _Action.exportPostman,
        child: Text(context.l10n.sbCopyPostman),
      ),
    PopupMenuItem(value: _Action.delete, child: Text(context.l10n.sbDelete)),
  ];

  void _movedToast(BuildContext context, String id, Undo undo) {
    final name = ref.read(repositoryProvider).node(id).name;
    showToast(
      context,
      context.l10n.toastMoved(name),
      onUndo: undo,
      undoLabel: context.l10n.undo,
    );
  }

  Future<void> _newCollection(BuildContext context) async {
    final name = await askName(
      context,
      title: context.l10n.sbNewCollection,
      action: context.l10n.sbCreate,
    );
    if (name == null) return;
    ref.read(treeActionsProvider).newCollection(name);
  }

  Future<void> _run(BuildContext context, _Action action, NodeInfo node) async {
    final l10n = context.l10n;
    final actions = ref.read(treeActionsProvider);
    switch (action) {
      case _Action.newRequest:
        final name = await askName(
          context,
          title: l10n.sbNewRequest,
          action: l10n.sbCreate,
        );
        if (name == null) return;
        final id = actions.newRequest(node.id, name: name);
        widget.onOpenRequest?.call(id);
      case _Action.newFolder:
        if (!context.mounted) return;
        final name = await askName(
          context,
          title: l10n.sbNewFolder,
          action: l10n.sbCreate,
        );
        if (name != null) actions.newFolder(node.id, name);
      case _Action.rename:
        final name = await askName(
          context,
          title: l10n.sbRename,
          initial: node.name,
        );
        if (name != null) actions.rename(node.id, name);
      case _Action.settings:
        await Navigator.of(context).push(
          MaterialPageRoute<void>(
            builder: (_) => ContainerSettingsPage(containerId: node.id),
          ),
        );
      case _Action.run:
        await Navigator.of(context).push(
          MaterialPageRoute<void>(
            builder: (_) => RunnerPage(containerId: node.id),
          ),
        );
      case _Action.duplicate:
        actions.duplicate(node.id);
      case _Action.moveUp:
        final undo = actions.nudge(node.id, -1);
        if (undo != null && context.mounted) {
          _movedToast(context, node.id, undo);
        }
      case _Action.moveDown:
        final undo = actions.nudge(node.id, 1);
        if (undo != null && context.mounted) {
          _movedToast(context, node.id, undo);
        }
      case _Action.versions:
        await showRevisions(context, ref, node.id);
      case _Action.copyCurl:
        await _copy(
          context,
          requestAsCurl(ref.read(sessionProvider), node.id),
          l10n.sbCurlCopied,
        );
      case _Action.toggleFavourite:
        final repo = ref.read(repositoryProvider);
        setState(() => repo.setFavourite(node.id, !repo.isFavourite(node.id)));
      case _Action.generateCode:
        await showDialog<void>(
          context: context,
          builder: (_) => CodeDialog(requestId: node.id),
        );
      case _Action.exportPostman:
        await _copy(
          context,
          exportCollectionJson(ref.read(sessionProvider), node.id),
          l10n.sbPostmanCopied,
        );
      case _Action.delete:
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

  Future<void> _import(BuildContext context) async {
    final text = await showDialog<String>(
      context: context,
      builder: (_) => const _ImportDialog(),
    );
    if (text == null || !context.mounted) return;
    final messenger = ScaffoldMessenger.of(context);
    try {
      final r = importText(ref.read(sessionProvider), text);
      final warn = r.warnings.isEmpty
          ? ''
          : context.l10n.sbImportNotes(r.warnings.length, r.warnings.first);
      messenger.showSnackBar(SnackBar(content: Text('${r.message}$warn')));
      final id = r.nodeId;
      if (id != null) {
        ref.read(expandedProvider.notifier).expand(id);
      }
    } on FormatException catch (e) {
      messenger.showSnackBar(SnackBar(content: Text(e.message)));
    }
  }
}

class _ImportDialog extends StatefulWidget {
  const _ImportDialog();

  @override
  State<_ImportDialog> createState() => _ImportDialogState();
}

class _ImportDialogState extends State<_ImportDialog> {
  final _controller = TextEditingController();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      // Scrolls when the window is short or the keyboard is up.
      scrollable: true,
      title: Text(context.l10n.sbImport),
      content: SizedBox(
        width: 520,
        child: TextField(
          key: const Key('import-text'),
          controller: _controller,
          autofocus: true,
          maxLines: 12,
          decoration: InputDecoration(hintText: context.l10n.sbImportHint),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: Text(context.l10n.sbCancel),
        ),
        FilledButton(
          key: const Key('import-confirm'),
          onPressed: () => Navigator.pop(context, _controller.text),
          child: Text(context.l10n.sbImport),
        ),
      ],
    );
  }
}
