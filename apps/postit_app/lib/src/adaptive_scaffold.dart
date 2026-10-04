import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'layout_class.dart';
import 'pages/environments_page.dart';
import 'pages/history_page.dart';
import 'pages/search_dialog.dart';
import 'settings_page.dart';
import 'state/editor_state.dart';
import 'state/session.dart';
import 'state/tree_state.dart';
import 'widgets/collections_sidebar.dart';
import 'widgets/request_editor.dart';

enum _Destination {
  collections(Icons.folder_outlined, Icons.folder, 'Collections'),
  history(Icons.history, Icons.history, 'History'),
  environments(Icons.tune_outlined, Icons.tune, 'Environments'),
  settings(Icons.settings_outlined, Icons.settings, 'Settings');

  const _Destination(this.icon, this.selectedIcon, this.label);

  final IconData icon;
  final IconData selectedIcon;
  final String label;
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
    if (id != null) ref.read(tabsProvider.notifier).close(id);
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
        const SingleActivator(LogicalKeyboardKey.keyK, control: true): _search,
        const SingleActivator(LogicalKeyboardKey.keyK, meta: true): _search,
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
      appBar: AppBar(title: Text(_selected.label)),
      body: _content(),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _selected.index,
        onDestinationSelected: _select,
        destinations: [
          for (final d in _Destination.values)
            NavigationDestination(
              icon: Icon(d.icon),
              selectedIcon: Icon(d.selectedIcon),
              label: d.label,
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
                  label: Text(d.label),
                ),
            ],
          ),
          const VerticalDivider(width: 1),
          if (sidebar &&
              _sidebarVisible &&
              _selected == _Destination.collections) ...[
            SizedBox(width: 280, child: _sidebar()),
            const VerticalDivider(width: 1),
          ],
          Expanded(child: _content()),
        ],
      ),
    );
  }

  Widget _sidebar() => const CollectionsSidebar();

  bool _expanded = false;

  Widget _activeRequest() {
    final active = ref.watch(tabsProvider).active;
    if (active == null) {
      return const Center(child: Text('Select or create a request'));
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
                  selected: id == active,
                  onTap: () => ref.read(tabsProvider.notifier).activate(id),
                  onClose: () => ref.read(tabsProvider.notifier).close(id),
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

  Widget _content() {
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

class _TabChip extends StatelessWidget {
  const _TabChip({
    super.key,
    required this.title,
    required this.selected,
    required this.onTap,
    required this.onClose,
  });

  final String title;
  final bool selected;
  final VoidCallback onTap;
  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.only(left: 12),
        decoration: BoxDecoration(
          border: Border(
            bottom: BorderSide(
              width: 2,
              color: selected
                  ? Theme.of(context).colorScheme.primary
                  : Colors.transparent,
            ),
          ),
        ),
        child: Row(
          children: [
            Text(title),
            IconButton(
              tooltip: 'Close tab',
              icon: const Icon(Icons.close, size: 14),
              onPressed: onClose,
            ),
          ],
        ),
      ),
    );
  }
}
