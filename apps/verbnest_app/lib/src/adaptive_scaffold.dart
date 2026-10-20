import 'widgets/ui/still_route.dart';

import 'package:material_ui/material_ui.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../l10n/l10n.dart';
import 'layout_class.dart';
import 'macos_menu.dart';
import 'pages/command_palette.dart';
import 'pages/environments_page.dart';
import 'pages/history_page.dart';
import 'pages/search_dialog.dart';
import 'settings_page.dart';
import 'state/editor_state.dart';
import 'state/session.dart';

import 'package:verbnest_storage/verbnest_storage.dart';

import 'state/tree_state.dart';
import 'state/variables.dart';
import 'widgets/collections_sidebar.dart';
import 'widgets/request_editor.dart';
import 'widgets/scaffold_parts.dart';
import 'widgets/status_bar.dart';
import 'widgets/ui/still_nav.dart';
import 'widgets/ui/toast.dart';
import 'widgets/ui/ui.dart';

/// The product name; it is not translated.
const kAppName = 'VerbNest';

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
      // Environments are reachable without a mouse too.
      PaletteEntry(
        id: 'env-none',
        title: l.cmdNoEnvironment,
        icon: Icons.tune,
        run: () => ref.read(activeEnvProvider.notifier).select(null),
      ),
      for (final e in ref.read(environmentsProvider))
        PaletteEntry(
          id: 'env-${e.id}',
          title: l.cmdSwitchEnv(e.name),
          icon: Icons.tune,
          run: () => ref.read(activeEnvProvider.notifier).select(e.id),
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
    showShortcutsDialog(context, [
      (l.cmdNewRequest, _combo('N')),
      (l.cmdSend, _combo('↵')),
      (l.cmdSearch, _combo('⇧F')),
      (l.cmdToggleSidebar, _combo('\\')),
      (l.cmdCloseTab, _combo('W')),
      (l.cmdShortcuts, _combo('/')),
    ]);
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
    return MacMenuBar(
      actions: MenuActions(
        newRequest: _newRequest,
        closeTab: _closeActive,
        search: _search,
        send: _sendActive,
        palette: _palette,
        toggleSidebar: _toggleSidebar,
        shortcuts: _showShortcuts,
      ),
      child: CallbackShortcuts(
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
          const SingleActivator(LogicalKeyboardKey.keyK, control: true):
              _palette,
          const SingleActivator(LogicalKeyboardKey.keyK, meta: true): _palette,
          const SingleActivator(
            LogicalKeyboardKey.keyF,
            control: true,
            shift: true,
          ): _search,
          const SingleActivator(
            LogicalKeyboardKey.keyF,
            meta: true,
            shift: true,
          ): _search,
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
      ),
    );
  }

  Widget _layout() {
    return LayoutBuilder(
      builder: (context, constraints) {
        final byWidth = LayoutClass.forWidth(constraints.maxWidth);
        // A short window (a landscape phone) has no height for a list beside
        // an editor, however wide it is: it gets the one-pane layout.
        final short =
            HeightClass.forHeight(constraints.maxHeight) == HeightClass.compact;
        final layout = short && byWidth.atLeast(LayoutClass.expanded)
            ? LayoutClass.medium
            : byWidth;
        // List and detail side by side from expanded (840 dp) upwards.
        _expanded = layout.atLeast(LayoutClass.expanded);
        return switch (layout) {
          LayoutClass.compact => _compact(),
          LayoutClass.medium => _withRail(sidebar: false),
          // Large and extra large: a permanent drawer instead of the rail.
          LayoutClass.large ||
          LayoutClass.extraLarge => _withRail(sidebar: true, drawer: true),
          _ => _withRail(sidebar: true),
        };
      },
    );
  }

  Widget _compact() {
    return Scaffold(
      key: const Key('layout-compact'),
      appBar: AppBar(title: Text(_selected.label(context))),
      body: _content(),
      bottomNavigationBar: StillNavigationBar(
        selectedIndex: _selected.index,
        onDestinationSelected: _select,
        destinations: _still(),
      ),
    );
  }

  Widget _withRail({required bool sidebar, bool drawer = false}) {
    return Scaffold(
      key: Key(sidebar ? 'layout-expanded' : 'layout-medium'),
      body: Column(
        children: [
          Expanded(
            child: Row(
              children: [
                if (drawer)
                  _navDrawer()
                else
                  // Scrolls when the window is too short for four destinations.
                  LayoutBuilder(
                    builder: (context, c) => SingleChildScrollView(
                      child: ConstrainedBox(
                        constraints: BoxConstraints(minHeight: c.maxHeight),
                        child: IntrinsicHeight(
                          child: StillNavigationRail(
                            selectedIndex: _selected.index,
                            onDestinationSelected: _select,
                            destinations: _still(),
                          ),
                        ),
                      ),
                    ),
                  ),
                const VerticalDivider(width: 1),
                if (sidebar && _selected == _Destination.collections)
                  // Hidden means unmounted; the sidebar opens and closes at once.
                  if (_sidebarVisible)
                    Row(
                      children: [
                        SizedBox(width: _sidebarWidth, child: _sidebar()),
                        _sidebarHandle(),
                      ],
                    ),
                Expanded(child: _content()),
              ],
            ),
          ),
          // Desktop-size windows get a status bar; a tablet has no room.
          if (sidebar) const StatusBar(),
        ],
      ),
    );
  }

  Widget _navDrawer() => AppNavDrawer(
    selectedIndex: _selected.index,
    onSelect: _select,
    destinations: _still(),
    appName: kAppName,
  );

  List<StillDestination> _still() => [
    for (final d in _Destination.values)
      StillDestination(
        icon: d.icon,
        selectedIcon: d.selectedIcon,
        label: d.label(context),
      ),
  ];

  // A Material, not a ColoredBox: list rows paint their ink on the nearest
  // Material and a ColoredBox would hide it.
  Widget _sidebar() => Material(
    color: Theme.of(context).colorScheme.surfaceContainerLow,
    child: const CollectionsSidebar(),
  );

  double _sidebarWidth = 280;
  static const _minSidebar = 200.0, _maxSidebar = 480.0;

  Widget _sidebarHandle() => SidebarHandle(
    onReset: () => setState(() => _sidebarWidth = 280),
    onDrag: (dx) => setState(
      () =>
          _sidebarWidth = (_sidebarWidth + dx).clamp(_minSidebar, _maxSidebar),
    ),
  );

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
    return Column(
      children: [
        TabStrip(onClose: _closeTab),
        const Divider(height: 1),
        Expanded(
          child: RequestEditor(key: ValueKey(active), requestId: active),
        ),
      ],
    );
  }

  void _openFullScreen(String id) {
    Navigator.of(context).push(
      StillPageRoute<void>(
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
    // Pages swap at once.
    return KeyedSubtree(key: ValueKey('$_selected-$_expanded'), child: _page());
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
