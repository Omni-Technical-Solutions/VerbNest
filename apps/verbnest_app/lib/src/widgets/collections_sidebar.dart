import 'dart:async';

import 'package:material_ui/material_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:verbnest_storage/verbnest_storage.dart';

import '../pages/search_dialog.dart';
import '../pages/workspaces_dialog.dart';
import '../workspace_host.dart';
import '../state/import_actions.dart';
import '../state/session.dart';
import '../state/sidebar_rows.dart';
import '../state/tree_state.dart';
import '../theme.dart';
import 'import_dialog.dart';
import 'sidebar_actions.dart';
import 'ui/ui.dart';
import 'name_dialog.dart';
import '../../l10n/l10n.dart';
import 'ui/toast.dart';
import 'ui/still_tooltip.dart';

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
          StillIconButton(
            key: const Key('favourites-filter'),
            tooltip: _favOnly ? context.l10n.sbShowAll : context.l10n.sbShowFav,
            icon: Icon(_favOnly ? Icons.star : Icons.star_border),
            onPressed: () => setState(() => _favOnly = !_favOnly),
          ),
          PopupMenuButton<String>(
            popUpAnimationStyle: AnimationStyle.noAnimation,
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
                  unawaited(_import(context));
                case 'workspaces':
                  unawaited(showWorkspaces(context, ref));
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
          StillIconButton(
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
          if (undo != null) movedToast(context, ref, d.data, undo);
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
          // The chevron points down when open: it turns at once.
          RotatedBox(
            quarterTurns: expanded ? 1 : 0,
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
    return PopupMenuButton<SidebarAction>(
      popUpAnimationStyle: AnimationStyle.noAnimation,
      key: Key('menu-${node.id}'),
      tooltip: context.l10n.sbActions,
      icon: const Icon(Icons.more_vert, size: 18),
      onSelected: (a) => _run(context, a, node),
      itemBuilder: (_) => sidebarMenuItems(context, ref, node),
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
    final action = await showMenu<SidebarAction>(
      popUpAnimationStyle: AnimationStyle.noAnimation,
      context: context,
      position: RelativeRect.fromRect(
        position & const Size(1, 1),
        Offset.zero & overlay.size,
      ),
      items: sidebarMenuItems(context, ref, node),
    );
    if (action != null && context.mounted) {
      unawaited(_run(context, action, node));
    }
  }

  Future<void> _run(
    BuildContext context,
    SidebarAction action,
    NodeInfo node,
  ) => runSidebarAction(
    context,
    ref,
    action,
    node,
    onOpenRequest: widget.onOpenRequest,
    onChanged: () => setState(() {}),
  );

  Future<void> _newCollection(BuildContext context) async {
    final name = await askName(
      context,
      title: context.l10n.sbNewCollection,
      action: context.l10n.sbCreate,
    );
    if (name == null) return;
    ref.read(treeActionsProvider).newCollection(name);
  }

  Future<void> _import(BuildContext context) async {
    final text = await showDialog<String>(
      animationStyle: AnimationStyle.noAnimation,
      context: context,
      builder: (_) => const ImportDialog(),
    );
    if (text == null || !context.mounted) return;
    final messenger = ScaffoldMessenger.of(context);
    try {
      final r = importText(ref.read(sessionProvider), text);
      final warn = r.warnings.isEmpty
          ? ''
          : context.l10n.sbImportNotes(r.warnings.length, r.warnings.first);
      messenger.showSnackBar(
        snackBarAnimationStyle: AnimationStyle.noAnimation,
        SnackBar(content: Text('${r.message}$warn')),
      );
      final id = r.nodeId;
      if (id != null) {
        ref.read(expandedProvider.notifier).expand(id);
      }
    } on FormatException catch (e) {
      messenger.showSnackBar(
        snackBarAnimationStyle: AnimationStyle.noAnimation,
        SnackBar(content: Text(e.message)),
      );
    }
  }
}
