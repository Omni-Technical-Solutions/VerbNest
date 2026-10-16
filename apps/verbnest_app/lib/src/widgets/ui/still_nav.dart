import 'package:material_ui/material_ui.dart';

import '../../theme.dart';

/// One place in the app's navigation.
class StillDestination {
  const StillDestination({
    required this.icon,
    required this.selectedIcon,
    required this.label,
  });

  final IconData icon;
  final IconData selectedIcon;
  final String label;
}

// Material's navigation bar, rail and drawer animate their selection (the
// indicator grows in and the icon swaps over about 300 ms, with no switch to
// turn that off). These draw the same three navigations, in the same Material 3
// shapes and colours, and a selection is simply there.

Widget _pill(BuildContext context, bool selected, Widget icon, double width) {
  final scheme = Theme.of(context).colorScheme;
  return Container(
    width: width,
    height: 32,
    alignment: Alignment.center,
    decoration: BoxDecoration(
      color: selected ? scheme.secondaryContainer : Colors.transparent,
      borderRadius: BorderRadius.circular(16),
    ),
    child: IconTheme(
      data: IconThemeData(
        size: 24,
        color: selected ? scheme.onSecondaryContainer : scheme.onSurfaceVariant,
      ),
      child: icon,
    ),
  );
}

TextStyle _label(BuildContext context, bool selected) {
  final scheme = Theme.of(context).colorScheme;
  return (Theme.of(context).textTheme.labelMedium ?? const TextStyle())
      .copyWith(
        color: selected ? scheme.onSurface : scheme.onSurfaceVariant,
        fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
      );
}

/// One destination of the bar or the rail: an icon in a pill, with the label
/// under it. It is at least [minHeight] tall and grows with large text.
class _StackedItem extends StatelessWidget {
  const _StackedItem({
    required this.destination,
    required this.selected,
    required this.onTap,
    required this.pillWidth,
    required this.minHeight,
  });

  final StillDestination destination;
  final bool selected;
  final VoidCallback onTap;
  final double pillWidth;
  final double minHeight;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      selected: selected,
      child: InkWell(
        onTap: onTap,
        child: ConstrainedBox(
          constraints: BoxConstraints(minHeight: minHeight),
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 12),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                _pill(
                  context,
                  selected,
                  Icon(selected ? destination.selectedIcon : destination.icon),
                  pillWidth,
                ),
                const SizedBox(height: 4),
                // Shrinks to fit the width rather than cutting the label.
                FittedBox(
                  fit: BoxFit.scaleDown,
                  child: Text(
                    destination.label,
                    style: _label(context, selected),
                    maxLines: 1,
                    softWrap: false,
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

/// The bottom navigation bar of a phone.
class StillNavigationBar extends StatelessWidget {
  const StillNavigationBar({
    super.key,
    required this.destinations,
    required this.selectedIndex,
    required this.onDestinationSelected,
  });

  final List<StillDestination> destinations;
  final int selectedIndex;
  final ValueChanged<int> onDestinationSelected;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Theme.of(context).colorScheme.surfaceContainer,
      child: SafeArea(
        top: false,
        child: IntrinsicHeight(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              for (var i = 0; i < destinations.length; i++)
                Expanded(
                  child: _StackedItem(
                    destination: destinations[i],
                    selected: i == selectedIndex,
                    onTap: () => onDestinationSelected(i),
                    pillWidth: 64,
                    minHeight: 80,
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

/// The navigation rail of a tablet or a small desktop window.
class StillNavigationRail extends StatelessWidget {
  const StillNavigationRail({
    super.key,
    required this.destinations,
    required this.selectedIndex,
    required this.onDestinationSelected,
  });

  final List<StillDestination> destinations;
  final int selectedIndex;
  final ValueChanged<int> onDestinationSelected;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Theme.of(context).colorScheme.surfaceContainerLow,
      child: SizedBox(
        width: 80,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(height: 8),
            for (var i = 0; i < destinations.length; i++)
              _StackedItem(
                destination: destinations[i],
                selected: i == selectedIndex,
                onTap: () => onDestinationSelected(i),
                pillWidth: 56,
                minHeight: 72,
              ),
          ],
        ),
      ),
    );
  }
}

/// The permanent navigation drawer of a large window: a header, then the
/// destinations with their labels beside the icons.
class StillNavigationDrawer extends StatelessWidget {
  const StillNavigationDrawer({
    super.key,
    required this.header,
    required this.destinations,
    required this.selectedIndex,
    required this.onDestinationSelected,
  });

  final Widget header;
  final List<StillDestination> destinations;
  final int selectedIndex;
  final ValueChanged<int> onDestinationSelected;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Material(
      color: scheme.surfaceContainerLow,
      child: ListView(
        padding: EdgeInsets.zero,
        children: [
          header,
          for (var i = 0; i < destinations.length; i++)
            Padding(
              padding: const EdgeInsets.symmetric(
                horizontal: Space.sm,
                vertical: 2,
              ),
              child: Semantics(
                button: true,
                selected: i == selectedIndex,
                child: InkWell(
                  borderRadius: BorderRadius.circular(28),
                  onTap: () => onDestinationSelected(i),
                  child: Container(
                    height: 56,
                    padding: const EdgeInsets.symmetric(horizontal: Space.lg),
                    decoration: BoxDecoration(
                      color: i == selectedIndex
                          ? scheme.secondaryContainer
                          : Colors.transparent,
                      borderRadius: BorderRadius.circular(28),
                    ),
                    child: Row(
                      children: [
                        Icon(
                          i == selectedIndex
                              ? destinations[i].selectedIcon
                              : destinations[i].icon,
                          size: 24,
                          color: i == selectedIndex
                              ? scheme.onSecondaryContainer
                              : scheme.onSurfaceVariant,
                        ),
                        const SizedBox(width: Space.md),
                        Expanded(
                          child: Text(
                            destinations[i].label,
                            style:
                                (Theme.of(context).textTheme.labelLarge ??
                                        const TextStyle())
                                    .copyWith(
                                      color: i == selectedIndex
                                          ? scheme.onSecondaryContainer
                                          : scheme.onSurfaceVariant,
                                      fontWeight: i == selectedIndex
                                          ? FontWeight.w700
                                          : FontWeight.w500,
                                    ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}
