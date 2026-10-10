import 'package:flutter/gestures.dart' show kTertiaryButton;
import 'package:material_ui/material_ui.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../l10n/l10n.dart';
import 'layout_class.dart';
import 'pages/command_palette.dart';
import 'pages/environments_page.dart';
import 'pages/history_page.dart';
import 'pages/search_dialog.dart';
import 'settings_page.dart';
import 'state/editor_state.dart';
import 'state/session.dart';

import 'package:verbnest_storage/verbnest_storage.dart';

import 'state/tree_state.dart';
import 'theme.dart';
import 'widgets/collections_sidebar.dart';
import 'widgets/request_editor.dart';
import 'widgets/ui/toast.dart';
import 'widgets/ui/ui.dart';

enum _Destination {
  collections(Icons.folder_outlined, Icons.folder),
  history(Icons.history, Icons.history),
  environments(Icons.tune_outlined, Icons.tune),
  settings(Icons.settings_outlined, Icons.settings);

  const _Destination(this.icon, this.selectedIcon);

  final IconData icon;
  final IconData selectedIcon;

  String label(BuildContext context) {
    final l = context.l10n;
    return switch (this) {
      collections => l.navCollections,
      history => l.navHistory,
      environments => l.navEnvironments,
      settings => l.navSettings,
    };
  }
}

/// Picks navigation by form factor: bottom bar on phones, rail on tablets,
/// rail plus a persistent sidebar on desktop (constitution III.3).
class AdaptiveScaffold extends ConsumerStatefulWidget {
  const AdaptiveScaffold({super.key});

  @override
  ConsumerState<AdaptiveScaffold> createState() => _AdaptiveScaffoldState();
}

class _AdaptiveScaffoldState extends ConsumerState<AdaptiveScaffold> {
  _Destination _selected = _Destination.collections;

  void _select(int index) =>
      setState(() => _selected = _Destination.values[index]);

  void _sendActive() {
    final id = ref.read(tabsProvider).active;
    if (id != null && _selected == _Destination.collections) {
      ref.read(editorProvider(id).notifier).send();
    }
  }

  Future<void> _search() async {
    final hit = await runSearch(context, ref);
    if (hit != null && mounted) {
      setState(() => _selected = _Destination.collections);
    }
  }

  void _palette() {
    final l = context.l10n;
    final repo = ref.read(repositoryProvider);
    final entries = <PaletteEntry>[
      PaletteEntry(
        id: 'cmd-new-request',
        shortcut: _combo('N'),
        title: l.cmdNewRequest,
        icon: Icons.add,
        run: _newRequest,
      ),
      PaletteEntry(
        id: 'cmd-send',
        shortcut: _combo('↵'),
        title: l.cmdSend,
        icon: Icons.send,
        run: _sendActive,
      ),
      PaletteEntry(
        id: 'cmd-search',
        shortcut: _combo('⇧F'),
        title: l.cmdSearch,
        icon: Icons.manage_search,
        run: _search,
      ),
      PaletteEntry(
        id: 'cmd-toggle-sidebar',
        shortcut: _combo('\\'),
        title: l.cmdToggleSidebar,
        icon: Icons.view_sidebar_outlined,
        run: _toggleSidebar,
      ),
      PaletteEntry(
        id: 'cmd-close-tab',
        shortcut: _combo('W'),
        title: l.cmdCloseTab,
        icon: Icons.close,
        run: _closeActive,
      ),
      PaletteEntry(
        id: 'cmd-shortcuts',
        title: l.cmdShortcuts,
        icon: Icons.keyboard_outlined,
        shortcut: _combo('/'),
        run: _showShortcuts,
      ),
      for (final d in _Destination.values)
        PaletteEntry(
          id: 'go-${d.name}',
          group: PaletteGroup.navigate,
          title: l.cmdGoTo(d.label(context)),
          icon: d.icon,
          run: () => setState(() => _selected = d),
        ),
      for (final d in repo.searchDocuments())
        if (d.kind == NodeKind.request)
          PaletteEntry(
            id: 'req-${d.id}',
            group: PaletteGroup.request,
            title: d.name,
            subtitle: '${d.method ?? ''} ${d.url ?? ''}'.trim(),
            run: () {
              ref.read(tabsProvider.notifier).open(d.id);
              setState(() => _selected = _Destination.collections);
            },
          ),
    ];
    showCommandPalette(context, entries);
  }

  String _combo(String key) => '${_modKey()}+$key';

  void _showShortcuts() {
    final l = context.l10n;
    final rows = [
      (l.cmdNewRequest, _combo('N')),
      (l.cmdSend, _combo('↵')),
      (l.cmdSearch, _combo('⇧F')),
      (l.cmdToggleSidebar, _combo('\\')),
      (l.cmdCloseTab, _combo('W')),
      (l.cmdShortcuts, _combo('/')),
    ];
    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        key: const Key('shortcuts-dialog'),
        title: Text(l.cmdShortcuts),
        content: SizedBox(
          width: 360,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              for (final (title, keys) in rows)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 4),
                  child: Row(
                    children: [
                      Expanded(child: Text(title)),
                      Kbd(keys),
                    ],
                  ),
                ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text(l.shortcutsClose),
          ),
        ],
      ),
    );
  }

  void _newRequest() {
    final repo = ref.read(repositoryProvider);
    final tabs = ref.read(tabsProvider);
    final active = tabs.active;
    var parent = active == null ? null : repo.node(active).parentId;
    parent ??= repo.children(null).firstOrNull?.id;
    if (parent == null) return;
    ref.read(treeActionsProvider).newRequest(parent);
    setState(() => _selected = _Destination.collections);
  }

  void _saveActive() {
    final id = ref.read(tabsProvider).active;
    if (id != null) ref.read(editorProvider(id).notifier).flush();
  }

  void _toggleSidebar() => setState(() => _sidebarVisible = !_sidebarVisible);

  bool _sidebarVisible = true;

  void _closeActive() {
    final id = ref.read(tabsProvider).active;
    if (id != null) _closeTab(id);
  }

  void _closeTab(String id) {
    final name = ref.read(repositoryProvider).node(id).name;
    ref.read(tabsProvider.notifier).close(id);
    final l = context.l10n;
    showToast(
      context,
      l.tabClosedToast(name),
      onUndo: () => ref.read(tabsProvider.notifier).open(id),
      undoLabel: l.undo,
    );
  }

  @override
  Widget build(BuildContext context) {
    return CallbackShortcuts(
      bindings: {
        for (final mod in [
          const SingleActivator(LogicalKeyboardKey.enter, control: true),
          const SingleActivator(LogicalKeyboardKey.enter, meta: true),
        ])
          mod: _sendActive,
        const SingleActivator(LogicalKeyboardKey.slash, control: true):
            _showShortcuts,
        const SingleActivator(LogicalKeyboardKey.slash, meta: true):
            _showShortcuts,
        const SingleActivator(LogicalKeyboardKey.keyK, control: true): _palette,
        const SingleActivator(LogicalKeyboardKey.keyK, meta: true): _palette,
        const SingleActivator(
          LogicalKeyboardKey.keyF,
          control: true,
          shift: true,
        ): _search,
        const SingleActivator(LogicalKeyboardKey.keyF, meta: true, shift: true):
            _search,
        const SingleActivator(LogicalKeyboardKey.keyW, control: true):
            _closeActive,
        const SingleActivator(LogicalKeyboardKey.keyW, meta: true):
            _closeActive,
        for (final (key, fn) in <(LogicalKeyboardKey, VoidCallback)>[
          (LogicalKeyboardKey.keyN, _newRequest),
          (LogicalKeyboardKey.keyS, _saveActive),
          (LogicalKeyboardKey.backslash, _toggleSidebar),
        ]) ...{
          SingleActivator(key, control: true): fn,
          SingleActivator(key, meta: true): fn,
        },
        const SingleActivator(LogicalKeyboardKey.tab, control: true): () =>
            ref.read(tabsProvider.notifier).step(1),
        const SingleActivator(
          LogicalKeyboardKey.tab,
          control: true,
          shift: true,
        ): () =>
            ref.read(tabsProvider.notifier).step(-1),
      },
      child: Focus(autofocus: true, child: _layout()),
    );
  }

  Widget _layout() {
    return LayoutBuilder(
      builder: (context, constraints) {
        final layout = LayoutClass.forWidth(constraints.maxWidth);
        _expanded = layout == LayoutClass.expanded;
        return switch (layout) {
          LayoutClass.compact => _compact(),
          LayoutClass.medium => _withRail(sidebar: false),
          LayoutClass.expanded => _withRail(sidebar: true),
        };
      },
    );
  }

  Widget _compact() {
    return Scaffold(
      key: const Key('layout-compact'),
      appBar: AppBar(title: Text(_selected.label(context))),
      body: _content(),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _selected.index,
        onDestinationSelected: _select,
        destinations: [
          for (final d in _Destination.values)
            NavigationDestination(
              icon: Icon(d.icon),
              selectedIcon: Icon(d.selectedIcon),
              label: d.label(context),
            ),
        ],
      ),
    );
  }

  Widget _withRail({required bool sidebar}) {
    return Scaffold(
      key: Key(sidebar ? 'layout-expanded' : 'layout-medium'),
      body: Row(
        children: [
          NavigationRail(
            selectedIndex: _selected.index,
            onDestinationSelected: _select,
            labelType: NavigationRailLabelType.all,
            destinations: [
              for (final d in _Destination.values)
                NavigationRailDestination(
                  icon: Icon(d.icon),
                  selectedIcon: Icon(d.selectedIcon),
                  label: Text(d.label(context)),
                ),
            ],
          ),
          const VerticalDivider(width: 1),
          if (sidebar && _selected == _Destination.collections)
            TweenAnimationBuilder<double>(
              tween: Tween(end: _sidebarVisible ? 1 : 0),
              duration: Motion.of(context, Motion.base),
              curve: Motion.curve,
              // Fully collapsed means unmounted, as before the animation.
              builder: (context, t, child) => t == 0
                  ? const SizedBox.shrink()
                  : ClipRect(
                      child: Align(
                        alignment: AlignmentDirectional.centerStart,
                        widthFactor: t,
                        child: child,
                      ),
                    ),
              child: Row(
                children: [
                  SizedBox(width: _sidebarWidth, child: _sidebar()),
                  _sidebarHandle(),
                ],
              ),
            ),
          Expanded(child: _content()),
        ],
      ),
    );
  }

  // A Material, not a ColoredBox: list rows paint their ink on the nearest
  // Material and a ColoredBox would hide it.
  Widget _sidebar() => Material(
    color: Theme.of(context).colorScheme.surfaceContainerLow,
    child: const CollectionsSidebar(),
  );

  double _sidebarWidth = 280;
  static const _minSidebar = 200.0, _maxSidebar = 480.0;

  /// Divider that doubles as a drag handle; double-click resets the width.
  Widget _sidebarHandle() {
    final line = Theme.of(context).colorScheme.outlineVariant;
    return MouseRegion(
      cursor: SystemMouseCursors.resizeColumn,
      child: GestureDetector(
        key: const Key('sidebar-handle'),
        behavior: HitTestBehavior.opaque,
        onDoubleTap: () => setState(() => _sidebarWidth = 280),
        onHorizontalDragUpdate: (d) => setState(() {
          final dx = Directionality.of(context) == TextDirection.rtl
              ? -d.delta.dx
              : d.delta.dx;
          _sidebarWidth = (_sidebarWidth + dx).clamp(_minSidebar, _maxSidebar);
        }),
        child: SizedBox(
          width: 7,
          child: Center(child: Container(width: 1, color: line)),
        ),
      ),
    );
  }

  bool _expanded = false;

  Widget _activeRequest() {
    final active = ref.watch(tabsProvider).active;
    if (active == null) {
      return EmptyState(
        logo: true,
        icon: Icons.http,
        title: context.l10n.selectOrCreateRequest,
        hint: '${_modKey()} + N',
      );
    }
    ref.watch(workspaceVersionProvider);
    final tabs = ref.watch(tabsProvider);
    final repo = ref.read(repositoryProvider);
    return Column(
      children: [
        SizedBox(
          height: 40,
          child: ListView(
            scrollDirection: Axis.horizontal,
            children: [
              for (final id in tabs.open)
                _TabChip(
                  key: Key('tab-$id'),
                  title: repo.node(id).name,
                  method: repo.node(id).method,
                  selected: id == active,
                  onTap: () => ref.read(tabsProvider.notifier).activate(id),
                  onClose: () => _closeTab(id),
                ),
            ],
          ),
        ),
        const Divider(height: 1),
        Expanded(
          child: RequestEditor(key: ValueKey(active), requestId: active),
        ),
      ],
    );
  }

  void _openFullScreen(String id) {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => Scaffold(
          appBar: AppBar(
            title: Text(ref.read(repositoryProvider).node(id).name),
          ),
          body: RequestEditor(requestId: id),
        ),
      ),
    );
  }

  String _modKey() => switch (Theme.of(context).platform) {
    TargetPlatform.macOS || TargetPlatform.iOS => '⌘',
    _ => 'Ctrl',
  };

  Widget _content() {
    return AnimatedSwitcher(
      duration: Motion.of(context, Motion.base),
      switchInCurve: Motion.curve,
      child: KeyedSubtree(
        key: ValueKey('$_selected-$_expanded'),
        child: _page(),
      ),
    );
  }

  Widget _page() {
    return switch (_selected) {
      _Destination.settings => const SettingsPage(),
      _Destination.history => const HistoryPage(),
      _Destination.environments => const EnvironmentsPage(),
      _Destination.collections when !_expanded => CollectionsSidebar(
        onOpenRequest: _openFullScreen,
      ),
      _Destination.collections => _activeRequest(),
    };
  }
}

class _TabChip extends StatefulWidget {
  const _TabChip({
    super.key,
    required this.title,
    required this.method,
    required this.selected,
    required this.onTap,
    required this.onClose,
  });

  final String title;
  final String? method;
  final bool selected;
  final VoidCallback onTap;
  final VoidCallback onClose;

  @override
  State<_TabChip> createState() => _TabChipState();
}

class _TabChipState extends State<_TabChip> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final selected = widget.selected;
    return MouseRegion(
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      child: Listener(
        // Middle-click closes, like a browser tab.
        onPointerDown: (e) {
          if (e.buttons == kTertiaryButton) widget.onClose();
        },
        child: InkWell(
          onTap: widget.onTap,
          child: AnimatedContainer(
            duration: Motion.of(context, Motion.base),
            curve: Motion.curve,
            padding: const EdgeInsetsDirectional.only(start: Space.md),
            decoration: BoxDecoration(
              color: selected
                  ? scheme.primaryContainer.withValues(alpha: 0.3)
                  : _hover
                  ? scheme.onSurface.withValues(alpha: 0.05)
                  : Colors.transparent,
              border: Border(
                bottom: BorderSide(
                  width: 2,
                  color: selected ? scheme.primary : Colors.transparent,
                ),
              ),
            ),
            child: Row(
              children: [
                if (widget.method != null) ...[
                  MethodBadge(widget.method!, width: 34),
                ],
                Text(
                  widget.title,
                  style: TextStyle(
                    fontWeight: selected ? FontWeight.w600 : FontWeight.normal,
                  ),
                ),
                Opacity(
                  opacity: selected || _hover ? 1 : 0.4,
                  child: IconButton(
                    tooltip: context.l10n.closeTab,
                    icon: const Icon(Icons.close, size: 14),
                    onPressed: widget.onClose,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
