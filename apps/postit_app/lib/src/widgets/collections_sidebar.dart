import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:postit_storage/postit_storage.dart';

import '../state/session.dart';
import '../state/sidebar_rows.dart';
import '../state/tree_state.dart';
import 'name_dialog.dart';

enum _Action {
  newRequest,
  newFolder,
  rename,
  duplicate,
  moveUp,
  moveDown,
  delete,
}

/// The collections tree with filter and per-item actions (FR-COL-001/003).
///
/// Reordering uses move up/down menu items, which work with touch and
/// keyboard; drag and drop is a later addition.
class CollectionsSidebar extends ConsumerStatefulWidget {
  const CollectionsSidebar({super.key, this.onOpenRequest});

  /// Called after a request is chosen; compact layouts use it to navigate.
  final void Function(String requestId)? onOpenRequest;

  @override
  ConsumerState<CollectionsSidebar> createState() => _CollectionsSidebarState();
}

class _CollectionsSidebarState extends ConsumerState<CollectionsSidebar> {
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
          child: rows.isEmpty
              ? _empty(context)
              : ListView.builder(
                  itemCount: rows.length,
                  itemBuilder: (context, i) => _tile(context, rows[i], active),
                ),
        ),
      ],
    );
  }

  Widget _header(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 8, 4, 4),
      child: Row(
        children: [
          Expanded(
            child: TextField(
              key: const Key('sidebar-filter'),
              decoration: const InputDecoration(
                isDense: true,
                prefixIcon: Icon(Icons.search, size: 18),
                hintText: 'Filter',
              ),
              onChanged: (v) => setState(() => _filter = v),
            ),
          ),
          IconButton(
            key: const Key('new-collection'),
            tooltip: 'New collection',
            icon: const Icon(Icons.create_new_folder_outlined),
            onPressed: () => _newCollection(context),
          ),
        ],
      ),
    );
  }

  Widget _empty(BuildContext context) {
    final filtering = _filter.trim().isNotEmpty;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Text(
          filtering
              ? 'Nothing matches "$_filter"'
              : 'No collections yet.\nCreate one to get started.',
          textAlign: TextAlign.center,
        ),
      ),
    );
  }

  Widget _tile(BuildContext context, SidebarRow row, String? active) {
    final node = row.node;
    final selected = node.id == active;
    return ListTile(
      key: Key('node-${node.id}'),
      dense: true,
      selected: selected,
      contentPadding: EdgeInsets.only(left: 12.0 + row.depth * 16, right: 0),
      leading: _leading(node, row.expanded),
      title: Text(node.name, overflow: TextOverflow.ellipsis),
      trailing: _menu(context, node),
      onTap: () => _onTap(node),
    );
  }

  Widget _leading(NodeInfo node, bool expanded) {
    if (node.isContainer) {
      return Icon(
        expanded ? Icons.folder_open : Icons.folder_outlined,
        size: 20,
      );
    }
    return SizedBox(
      width: 40,
      child: Text(
        _shortMethod(node.method ?? 'GET'),
        style: TextStyle(
          fontSize: 10,
          fontWeight: FontWeight.bold,
          color: _methodColor(node.method ?? 'GET'),
        ),
      ),
    );
  }

  String _shortMethod(String m) => switch (m.toUpperCase()) {
    'DELETE' => 'DEL',
    'OPTIONS' => 'OPT',
    'PATCH' => 'PATCH',
    final other => other.length > 5 ? other.substring(0, 5) : other,
  };

  Color _methodColor(String m) => switch (m.toUpperCase()) {
    'GET' => Colors.green.shade700,
    'POST' => Colors.orange.shade800,
    'PUT' => Colors.blue.shade700,
    'PATCH' => Colors.purple.shade600,
    'DELETE' => Colors.red.shade700,
    _ => Colors.grey.shade700,
  };

  void _onTap(NodeInfo node) {
    if (node.isContainer) {
      ref.read(expandedProvider.notifier).toggle(node.id);
      return;
    }
    ref.read(tabsProvider.notifier).open(node.id);
    widget.onOpenRequest?.call(node.id);
  }

  Widget _menu(BuildContext context, NodeInfo node) {
    return PopupMenuButton<_Action>(
      key: Key('menu-${node.id}'),
      tooltip: 'Actions',
      icon: const Icon(Icons.more_vert, size: 18),
      onSelected: (a) => _run(context, a, node),
      itemBuilder: (_) => [
        if (node.isContainer) ...const [
          PopupMenuItem(value: _Action.newRequest, child: Text('New request')),
          PopupMenuItem(value: _Action.newFolder, child: Text('New folder')),
        ],
        const PopupMenuItem(value: _Action.rename, child: Text('Rename')),
        const PopupMenuItem(value: _Action.duplicate, child: Text('Duplicate')),
        const PopupMenuItem(value: _Action.moveUp, child: Text('Move up')),
        const PopupMenuItem(value: _Action.moveDown, child: Text('Move down')),
        const PopupMenuItem(value: _Action.delete, child: Text('Delete')),
      ],
    );
  }

  Future<void> _newCollection(BuildContext context) async {
    final name = await askName(
      context,
      title: 'New collection',
      action: 'Create',
    );
    if (name == null) return;
    ref.read(treeActionsProvider).newCollection(name);
  }

  Future<void> _run(BuildContext context, _Action action, NodeInfo node) async {
    final actions = ref.read(treeActionsProvider);
    switch (action) {
      case _Action.newRequest:
        final name = await askName(
          context,
          title: 'New request',
          action: 'Create',
        );
        if (name == null) return;
        final id = actions.newRequest(node.id, name: name);
        widget.onOpenRequest?.call(id);
      case _Action.newFolder:
        if (!context.mounted) return;
        final name = await askName(
          context,
          title: 'New folder',
          action: 'Create',
        );
        if (name != null) actions.newFolder(node.id, name);
      case _Action.rename:
        final name = await askName(
          context,
          title: 'Rename',
          initial: node.name,
        );
        if (name != null) actions.rename(node.id, name);
      case _Action.duplicate:
        actions.duplicate(node.id);
      case _Action.moveUp:
        actions.nudge(node.id, -1);
      case _Action.moveDown:
        actions.nudge(node.id, 1);
      case _Action.delete:
        final ok = await confirm(
          context,
          title: 'Delete "${node.name}"?',
          message: node.isContainer
              ? 'This also deletes everything inside it.'
              : 'This cannot be undone.',
        );
        if (ok) actions.delete(node.id);
    }
  }
}
