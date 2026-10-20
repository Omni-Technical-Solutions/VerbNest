import 'package:material_ui/material_ui.dart';
import 'package:verbnest_core/verbnest_core.dart';

import '../../l10n/l10n.dart';
import '../theme.dart';
import 'result_table_sizing.dart';

/// One cell of the results table: the value on one line (numbers right-aligned
/// in tabular figures, objects and arrays in a smaller monospace), with the
/// selection and focus drawn, and a spoken label for a screen reader, which
/// activates it to see the value in full.
class TableValueCell extends StatelessWidget {
  const TableValueCell({
    super.key,
    required this.row,
    required this.col,
    required this.value,
    required this.columnName,
    required this.type,
    required this.width,
    required this.style,
    required this.muted,
    required this.matches,
    required this.selected,
    required this.focused,
    required this.onActivate,
  });

  /// The row's position in the sorted, filtered rows, and the column.
  final int row, col;
  final Object? value;
  final String columnName;
  final ColumnType type;
  final double width;
  final TextStyle style;

  /// For a null value.
  final TextStyle muted;

  /// How many rows match the filter (the "of" of the spoken label).
  final int matches;
  final bool selected;
  final bool focused;

  /// A screen reader's activation: select the cell and show its value.
  final VoidCallback onActivate;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final l10n = context.l10n;
    final v = value;
    final numeric = type == ColumnType.number && v is num;
    final Widget text = v == null
        ? Text(
            l10n.tableNull,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: muted,
          )
        : Text(
            TableColumnSizer.shownText(v),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: numeric
                ? style.copyWith(fontFeatures: kTabularFigures)
                : (v is Map || v is List)
                ? style.copyWith(
                    color: scheme.onSurfaceVariant,
                    fontFamily: kMonoFamily,
                    fontSize: 12,
                  )
                : style,
          );
    final spoken = v == null ? l10n.tableNull : cellText(v);
    return Semantics(
      label: l10n.tableCellLabel(
        columnName,
        row + 1,
        matches,
        spoken.length > 200 ? spoken.substring(0, 200) : spoken,
      ),
      selected: selected,
      onTap: onActivate,
      excludeSemantics: true,
      child: Container(
        key: ValueKey('table-cell-$row-$col'),
        width: width,
        padding: const EdgeInsets.symmetric(horizontal: 12),
        alignment: numeric ? Alignment.centerRight : Alignment.centerLeft,
        decoration: BoxDecoration(
          color: selected ? scheme.secondaryContainer : null,
          border: Border(
            right: BorderSide(color: scheme.outlineVariant),
            bottom: BorderSide(color: scheme.outlineVariant),
          ),
        ),
        foregroundDecoration: focused
            ? BoxDecoration(border: Border.all(color: scheme.primary, width: 2))
            : null,
        child: text,
      ),
    );
  }
}
