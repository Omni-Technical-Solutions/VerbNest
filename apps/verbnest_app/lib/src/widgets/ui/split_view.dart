import 'package:material_ui/material_ui.dart';

import '../../theme.dart';

/// Two panes with a draggable divider. [ratio] is the first pane's share.
class SplitView extends StatelessWidget {
  const SplitView({
    super.key,
    required this.axis,
    required this.ratio,
    required this.onRatioChanged,
    required this.first,
    required this.second,
    this.collapseFirst = false,
  });

  final Axis axis;
  final double ratio;
  final ValueChanged<double> onRatioChanged;
  final Widget first;
  final Widget second;

  /// Hide the first pane and give the second all the room. The first stays
  /// mounted (offstage), so its state, such as the selected tab, is kept.
  final bool collapseFirst;

  static const _handle = 10.0;

  @override
  Widget build(BuildContext context) {
    final vertical = axis == Axis.vertical;
    return LayoutBuilder(
      builder: (context, c) {
        final total = (vertical ? c.maxHeight : c.maxWidth) - _handle;
        if (total <= 0) return const SizedBox.shrink();
        // On a device pixel, so the panes, and the text in them, are not
        // drawn between pixels.
        final dpr = MediaQuery.devicePixelRatioOf(context);
        final firstSize = (total * ratio * dpr).roundToDouble() / dpr;
        final scheme = Theme.of(context).colorScheme;
        final divider = MouseRegion(
          cursor: vertical
              ? SystemMouseCursors.resizeRow
              : SystemMouseCursors.resizeColumn,
          child: GestureDetector(
            key: const Key('split-handle'),
            behavior: HitTestBehavior.opaque,
            onPanUpdate: (d) => onRatioChanged(
              (firstSize + (vertical ? d.delta.dy : d.delta.dx)) / total,
            ),
            child: SizedBox(
              width: vertical ? double.infinity : _handle,
              height: vertical ? _handle : double.infinity,
              child: Center(
                child: Container(
                  width: vertical ? 40 : 3,
                  height: vertical ? 3 : 40,
                  decoration: BoxDecoration(
                    color: scheme.outlineVariant,
                    borderRadius: BorderRadius.circular(Radii.sm),
                  ),
                ),
              ),
            ),
          ),
        );
        final children = [
          // Collapsed, the first pane stays in the tree (same place and type),
          // so neither it nor the second pane loses its state.
          Offstage(
            offstage: collapseFirst,
            child: SizedBox(
              width: vertical ? null : firstSize,
              height: vertical ? firstSize : null,
              child: first,
            ),
          ),
          if (collapseFirst) const SizedBox.shrink() else divider,
          Expanded(child: second),
        ];
        return vertical ? Column(children: children) : Row(children: children);
      },
    );
  }
}
