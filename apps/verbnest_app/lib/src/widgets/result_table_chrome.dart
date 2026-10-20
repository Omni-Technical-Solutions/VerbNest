import 'package:flutter/services.dart';
import 'package:material_ui/material_ui.dart';
import 'package:verbnest_core/verbnest_core.dart';

import '../../l10n/l10n.dart';
import '../theme.dart';
import 'ui/adaptive_dialog.dart';
import 'ui/toast.dart';

// The parts of the results table that are not the grid itself: the menu items,
// the footer, and the dialog that shows one cell in full.

/// The copy, select and save items of the results table menu. [column] adds
/// the items of a header's menu; [columnSorted] whether it is the sort column.
List<PopupMenuEntry<String>> tableMenuEntries(
  BuildContext context, {
  required bool hasSelection,
  required bool singleCell,
  required bool canSave,
  int? column,
  bool columnSorted = false,
}) {
  final l10n = context.l10n;
  return [
    PopupMenuItem(
      key: const Key('menu-copy-cells'),
      value: 'copy',
      enabled: hasSelection,
      child: Text(l10n.tableCopy),
    ),
    PopupMenuItem(
      key: const Key('menu-copy-headers'),
      value: 'copy-headers',
      enabled: hasSelection,
      child: Text(l10n.tableCopyWithHeaders),
    ),
    PopupMenuItem(
      key: const Key('menu-copy-csv'),
      value: 'csv',
      child: Text(l10n.tableCopyAsCsv),
    ),
    PopupMenuItem(
      key: const Key('menu-copy-json'),
      value: 'json',
      child: Text(l10n.tableCopyAsJson),
    ),
    PopupMenuItem(
      key: const Key('menu-copy-markdown'),
      value: 'markdown',
      child: Text(l10n.tableCopyAsMarkdown),
    ),
    const PopupMenuDivider(),
    PopupMenuItem(
      key: const Key('menu-select-all'),
      value: 'all',
      child: Text(l10n.tableSelectAll),
    ),
    if (column != null) ...[
      PopupMenuItem(
        key: const Key('menu-select-column'),
        value: 'column:$column',
        child: Text(l10n.tableSelectColumn),
      ),
      PopupMenuItem(
        key: const Key('menu-fit-column'),
        value: 'fit:$column',
        child: Text(l10n.tableFitColumn),
      ),
      if (columnSorted)
        PopupMenuItem(
          key: const Key('menu-clear-sort'),
          value: 'clear-sort',
          child: Text(l10n.tableClearSort),
        ),
    ],
    if (singleCell)
      PopupMenuItem(
        key: const Key('menu-view-value'),
        value: 'view',
        child: Text(l10n.tableViewValue),
      ),
    if (canSave) ...[
      const PopupMenuDivider(),
      PopupMenuItem(
        key: const Key('menu-save-csv'),
        value: 'save',
        child: Text(l10n.tableSaveCsv),
      ),
    ],
  ];
}

/// The row count, the selection size, and the copy and export menu.
class TableFooter extends StatelessWidget {
  const TableFooter({
    super.key,
    required this.table,
    required this.matches,
    required this.selectedCount,
    required this.touch,
    required this.onMenu,
    required this.entries,
  });

  final ResultTable table;

  /// Rows that match the filter.
  final int matches;
  final int selectedCount;
  final bool touch;
  final ValueChanged<String> onMenu;
  final List<PopupMenuEntry<String>> Function() entries;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final t = table;
    final l10n = context.l10n;
    final filtered = matches != t.rowCount;
    final parts = <String>[
      filtered
          ? l10n.tableFiltered(matches, t.rowCount)
          : l10n.tableSummary(t.rowCount, t.columnCount),
      if (filtered) l10n.tableColumns(t.columnCount),
      if (matches > ResultTable.maxGridRows)
        l10n.tableCapped(ResultTable.maxGridRows),
      if (t.columnsDropped > 0) l10n.tableColumnsDropped(t.columnsDropped),
      if (selectedCount > 1) l10n.tableSelected(selectedCount),
    ];
    // The copy and export menu sits at the end of the footer: a bar of its
    // own above the grid would cost every table a row.
    final size = touch ? 48.0 : 32.0;
    return Container(
      key: const Key('table-footer'),
      padding: const EdgeInsets.only(left: 12),
      decoration: BoxDecoration(
        border: Border(top: BorderSide(color: scheme.outlineVariant)),
      ),
      child: Row(
        children: [
          Expanded(
            child: Text(
              parts.join(' · '),
              style: Theme.of(context).textTheme.bodySmall
                  ?.copyWith(color: scheme.onSurfaceVariant),
            ),
          ),
          SizedBox(
            width: size,
            height: size,
            child: PopupMenuButton<String>(
              popUpAnimationStyle: AnimationStyle.noAnimation,
              key: const Key('table-actions'),
              tooltip: l10n.tableActions,
              icon: const Icon(Icons.more_vert),
              iconSize: 20,
              padding: EdgeInsets.zero,
              onSelected: onMenu,
              itemBuilder: (context) => entries(),
            ),
          ),
        ],
      ),
    );
  }
}

/// One cell in full, with a button that copies it.
void showTableValue(
  BuildContext context, {
  required String title,
  required Object? value,
}) {
  final l10n = context.l10n;
  showDetail(
    context,
    title: title,
    closeLabel: l10n.close,
    width: 520,
    content: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SelectableText(
          value == null ? l10n.tableNull : cellFull(value),
          key: const Key('table-value'),
          style: monoStyle(fontSize: 13),
        ),
        const SizedBox(height: 12),
        OutlinedButton.icon(
          key: const Key('table-value-copy'),
          icon: const Icon(Icons.copy, size: 18),
          label: Text(l10n.tableCopy),
          onPressed: () {
            Clipboard.setData(ClipboardData(text: cellFull(value)));
            showToast(context, l10n.tableCopied(1));
          },
        ),
      ],
    ),
  );
}
