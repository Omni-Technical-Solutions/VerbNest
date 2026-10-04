import 'package:flutter/material.dart';

import 'layout_class.dart';
import 'settings_page.dart';

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
class AdaptiveScaffold extends StatefulWidget {
  const AdaptiveScaffold({super.key});

  @override
  State<AdaptiveScaffold> createState() => _AdaptiveScaffoldState();
}

class _AdaptiveScaffoldState extends State<AdaptiveScaffold> {
  _Destination _selected = _Destination.collections;

  void _select(int index) =>
      setState(() => _selected = _Destination.values[index]);

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final layout = LayoutClass.forWidth(constraints.maxWidth);
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

  Widget _sidebar() => Center(child: Text('${_selected.label} sidebar'));

  Widget _content() {
    return switch (_selected) {
      _Destination.settings => const SettingsPage(),
      _ => Center(child: Text('${_selected.label} (coming soon)')),
    };
  }
}
