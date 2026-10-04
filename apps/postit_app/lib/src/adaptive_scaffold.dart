import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'layout_class.dart';
import 'settings_page.dart';
import 'state/session.dart';
import 'state/tree_state.dart';
import 'widgets/collections_sidebar.dart';

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

  @override
  Widget build(BuildContext context) {
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
          if (sidebar) ...[
            SizedBox(width: 280, child: _sidebar()),
            const VerticalDivider(width: 1),
          ],
          Expanded(child: _content()),
        ],
      ),
    );
  }

  Widget _sidebar() => _selected == _Destination.collections
      ? const CollectionsSidebar()
      : Center(child: Text('${_selected.label} sidebar'));

  bool _expanded = false;

  Widget _activeRequest() {
    final active = ref.watch(tabsProvider).active;
    if (active == null) {
      return const Center(child: Text('Select or create a request'));
    }
    ref.watch(workspaceVersionProvider);
    final node = ref.read(repositoryProvider).node(active);
    return Center(child: Text(node.name));
  }

  Widget _content() {
    return switch (_selected) {
      _Destination.settings => const SettingsPage(),
      _Destination.collections when !_expanded => const CollectionsSidebar(),
      _Destination.collections => _activeRequest(),
      _ => Center(child: Text('${_selected.label} (coming soon)')),
    };
  }
}
