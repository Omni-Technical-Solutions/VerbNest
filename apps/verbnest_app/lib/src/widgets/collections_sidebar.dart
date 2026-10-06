import 'package:flutter/material.dart';
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
import 'code_dialog.dart';
import 'name_dialog.dart';
import '../../l10n/l10n.dart';

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
          if (_hasHost(context))
            IconButton(
              key: const Key('workspaces'),
              tooltip: context.l10n.sbWorkspaces,
              icon: const Icon(Icons.workspaces_outline),
              onPressed: () => showWorkspaces(context, ref),
            ),
          IconButton(
            key: const Key('favourites-filter'),
            tooltip: _favOnly ? context.l10n.sbShowAll : context.l10n.sbShowFav,
            icon: Icon(_favOnly ? Icons.star : Icons.star_border),
            onPressed: () => setState(() => _favOnly = !_favOnly),
          ),
          IconButton(
            key: const Key('search'),
            tooltip: context.l10n.sbSearch,
            icon: const Icon(Icons.manage_search),
            onPressed: () async {
              final hit = await runSearch(context, ref);
              if (hit != null && hit.kind == NodeKind.request) {
                widget.onOpenRequest?.call(hit.id);
              }
            },
          ),
          IconButton(
            key: const Key('import'),
            tooltip: context.l10n.sbImport,
            icon: const Icon(Icons.file_download_outlined),
            onPressed: () => _import(context),
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
      return Center(
        key: const Key('no-favourites'),
        child: Text(context.l10n.sbNoFav),
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
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Text(
          filtering
              ? context.l10n.sbNoMatch(_filter)
              : context.l10n.sbNoCollections,
          textAlign: TextAlign.center,
        ),
      ),
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
          ref.read(treeActionsProvider).drop(d.data, node.id);
        } on StorageError catch (e) {
          ScaffoldMessenger.of(context)
              .showSnackBar(SnackBar(content: Text(e.message)));
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
                color: Colors.amber.shade700,
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
      tooltip: context.l10n.sbActions,
      icon: const Icon(Icons.more_vert, size: 18),
      onSelected: (a) => _run(context, a, node),
      itemBuilder: (_) => [
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
        PopupMenuItem(
          value: _Action.rename,
          child: Text(context.l10n.sbRename),
        ),
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
        PopupMenuItem(
          value: _Action.moveUp,
          child: Text(context.l10n.sbMoveUp),
        ),
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
        PopupMenuItem(
          value: _Action.delete,
          child: Text(context.l10n.sbDelete),
        ),
      ],
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
        actions.nudge(node.id, -1);
      case _Action.moveDown:
        actions.nudge(node.id, 1);
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
        if (ok) actions.delete(node.id);
    }
  }

  Future<void> _copy(BuildContext context, String text, String message) async {
    await Clipboard.setData(ClipboardData(text: text));
    if (!context.mounted) return;
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(message)));
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
