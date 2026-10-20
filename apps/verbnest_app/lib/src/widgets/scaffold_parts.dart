import 'package:flutter/gestures.dart' show kTertiaryButton;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

import '../../l10n/l10n.dart';
import '../state/session.dart';
import '../state/tree_state.dart';
import '../theme.dart';
import 'ui/ui.dart';
import 'ui/still_nav.dart';
import 'ui/still_tooltip.dart';

/// The open requests as a row of tabs. Drag a tab to reorder; the drag starts
/// at once (no long press) so it works with a mouse.
class TabStrip extends ConsumerWidget {
  const TabStrip({super.key, required this.onClose});

  final void Function(String id) onClose;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tabs = ref.watch(tabsProvider);
    final repo = ref.read(repositoryProvider);
    final notifier = ref.read(tabsProvider.notifier);
    return SizedBox(
      height: 40,
      child: ReorderableListView(
        scrollDirection: Axis.horizontal,
        buildDefaultDragHandles: false,
        proxyDecorator: (child, _, _) =>
            Material(color: Colors.transparent, child: child),
        onReorderItem: notifier.move,
        children: [
          for (final (i, id) in tabs.open.indexed)
            ReorderableDragStartListener(
              key: Key('tab-$id'),
              index: i,
              child: TabChip(
                title: repo.node(id).name,
                method: repo.node(id).method,
                selected: id == tabs.active,
                preview: id == tabs.preview,
                onTap: () => notifier.activate(id),
                onPin: () => notifier.pin(id),
                onClose: () => onClose(id),
              ),
            ),
        ],
      ),
    );
  }
}

/// The draggable divider between the sidebar and the editor; double-click
/// resets the width.
class SidebarHandle extends StatelessWidget {
  const SidebarHandle({super.key, required this.onDrag, required this.onReset});

  /// Called with the sideways movement in the reading direction.
  final void Function(double dx) onDrag;
  final VoidCallback onReset;

  @override
  Widget build(BuildContext context) {
    final line = Theme.of(context).colorScheme.outlineVariant;
    return MouseRegion(
      cursor: SystemMouseCursors.resizeColumn,
      child: GestureDetector(
        key: const Key('sidebar-handle'),
        behavior: HitTestBehavior.opaque,
        onDoubleTap: onReset,
        onHorizontalDragUpdate: (d) => onDrag(
          Directionality.of(context) == TextDirection.rtl
              ? -d.delta.dx
              : d.delta.dx,
        ),
        child: SizedBox(
          width: 7,
          child: Center(child: Container(width: 1, color: line)),
        ),
      ),
    );
  }
}

/// Material 3 permanent navigation drawer for large windows: the same
/// destinations as the rail, with labels beside the icons and the app name.
class AppNavDrawer extends StatelessWidget {
  const AppNavDrawer({
    super.key,
    required this.selectedIndex,
    required this.onSelect,
    required this.destinations,
    required this.appName,
  });

  final int selectedIndex;
  final ValueChanged<int> onSelect;
  final List<StillDestination> destinations;
  final String appName;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      key: const Key('nav-drawer'),
      width: 240,
      child: StillNavigationDrawer(
        selectedIndex: selectedIndex,
        onDestinationSelected: onSelect,
        destinations: destinations,
        header: Padding(
          padding: const EdgeInsets.fromLTRB(
            Space.xl,
            Space.lg,
            Space.lg,
            Space.md,
          ),
          child: Row(
            children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(Radii.sm),
                child: Image.asset(
                  'assets/logo.png',
                  width: 28,
                  height: 28,
                  errorBuilder: (_, _, _) =>
                      const SizedBox(width: 28, height: 28),
                ),
              ),
              const SizedBox(width: Space.md),
              Text(appName, style: Theme.of(context).textTheme.titleMedium),
            ],
          ),
        ),
      ),
    );
  }
}

/// The keyboard shortcuts as a list of (action, keys) rows.
void showShortcutsDialog(BuildContext context, List<(String, String)> rows) {
  final l = context.l10n;
  showDialog<void>(
    animationStyle: AnimationStyle.noAnimation,
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

/// One tab: the request's method and name and a close button.
class TabChip extends StatefulWidget {
  const TabChip({
    super.key,
    required this.title,
    required this.method,
    required this.selected,
    required this.preview,
    required this.onTap,
    required this.onPin,
    required this.onClose,
  });

  final String title;
  final String? method;
  final bool selected;

  /// A preview tab (italic) is replaced by the next single click.
  final bool preview;
  final VoidCallback onTap;
  final VoidCallback onPin;
  final VoidCallback onClose;

  @override
  State<TabChip> createState() => _TabChipState();
}

class _TabChipState extends State<TabChip> {
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
          onDoubleTap: widget.onPin,
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
                    fontStyle: widget.preview
                        ? FontStyle.italic
                        : FontStyle.normal,
                  ),
                ),
                Opacity(
                  opacity: selected || _hover ? 1 : 0.4,
                  child: StillIconButton(
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
