import 'package:material_ui/material_ui.dart';

import '../../l10n/l10n.dart';
import 'ui/still_tooltip.dart';

// The two parts of one column header of the results table, each a child of the
// header cell's Stack: the label (tap to sort, secondary press for the menu)
// and the handle on its right edge (drag to resize, double-tap to fit).

/// The name and type of a column, tappable to sort, with its menu.
class TableHeaderLabel extends StatelessWidget {
  const TableHeaderLabel({
    super.key,
    required this.index,
    required this.name,
    required this.typeName,
    required this.ascending,
    required this.nameStyle,
    required this.onSort,
    required this.onMenu,
  });

  final int index;
  final String name;
  final String typeName;

  /// Whether the column is the sort column, and which way; null when it is not.
  final bool? ascending;
  final TextStyle nameStyle;
  final VoidCallback onSort;

  /// Called with the global position where the menu should open.
  final ValueChanged<Offset> onMenu;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final scheme = Theme.of(context).colorScheme;
    final small = Theme.of(context).textTheme.bodySmall
        ?.copyWith(color: scheme.outline, fontSize: 11);
    final sorted = ascending;
    return Positioned.fill(
      child: StillTooltip(
        message: l10n.tableSortBy(name),
        child: Semantics(
          button: true,
          label: l10n.tableHeaderLabel(name, typeName),
          value: sorted == null
              ? null
              : (sorted
                    ? l10n.tableSortedAscending
                    : l10n.tableSortedDescending),
          onTap: onSort,
          excludeSemantics: true,
          child: GestureDetector(
            excludeFromSemantics: true,
            onSecondaryTapDown: (d) => onMenu(d.globalPosition),
            onLongPressStart: (d) => onMenu(d.globalPosition),
            child: InkWell(
              key: ValueKey('table-sort-$index'),
              onTap: onSort,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(12, 4, 12, 4),
                child: Row(
                  children: [
                    Expanded(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            name,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: nameStyle,
                          ),
                          Text(
                            typeName,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: small,
                          ),
                        ],
                      ),
                    ),
                    if (sorted != null)
                      Icon(
                        sorted ? Icons.arrow_upward : Icons.arrow_downward,
                        key: Key(
                          sorted
                              ? 'table-sort-asc-$index'
                              : 'table-sort-desc-$index',
                        ),
                        size: 16,
                      ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// The 12 dp strip on a header's right edge: drag to resize the column,
/// double-tap to fit it to its content.
class TableResizeHandle extends StatelessWidget {
  const TableResizeHandle({
    super.key,
    required this.index,
    required this.onResize,
    required this.onFit,
  });

  final int index;

  /// Called with how far the pointer moved sideways since the last update.
  final ValueChanged<double> onResize;
  final VoidCallback onFit;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Positioned(
      top: 0,
      bottom: 0,
      right: 0,
      width: 12,
      // Out of the accessibility tree: it is a 12 dp drag handle,
      // and "Fit column" is in the header menu.
      child: ExcludeSemantics(
        child: GestureDetector(
          key: ValueKey('table-resize-$index'),
          behavior: HitTestBehavior.opaque,
          onHorizontalDragUpdate: (d) => onResize(d.delta.dx),
          onDoubleTap: onFit,
          child: MouseRegion(
            cursor: SystemMouseCursors.resizeColumn,
            child: Align(
              alignment: Alignment.centerRight,
              child: Container(width: 1, color: scheme.outlineVariant),
            ),
          ),
        ),
      ),
    );
  }
}
