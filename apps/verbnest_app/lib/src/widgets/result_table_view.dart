import 'dart:math' as math;

import 'package:flutter/foundation.dart'
    show TargetPlatform, defaultTargetPlatform;
import 'package:material_ui/material_ui.dart';
import 'package:verbnest_core/verbnest_core.dart';

import '../../l10n/l10n.dart';
import '../theme.dart';

/// A read-only grid of a [ResultTable], in the manner of a database client's
/// results grid (FR-RES-008): the header and the row numbers stay in view
/// while the rest scrolls, columns resize by dragging the header's edge
/// (double-tap fits the content), a header tap sorts, and a footer counts rows.
///
/// Rows are fixed height and built lazily, so a result of tens of thousands of
/// rows scrolls without building them all.
class ResultTableView extends StatefulWidget {
  const ResultTableView({super.key, required this.table, this.filter = ''});

  final ResultTable table;

  /// Only rows with a cell containing this text (case-insensitive) show.
  final String filter;

  static const minColumnWidth = 60.0;
  static const maxColumnWidth = 800.0;
  static const _fitMin = 80.0;
  static const _fitMax = 360.0;
  static const _rowNumberWidth = 56.0;

  @override
  State<ResultTableView> createState() => _ResultTableViewState();
}

class _ResultTableViewState extends State<ResultTableView> {
  final _h = ScrollController();
  final _v = ScrollController();
  List<double>? _widths;
  List<int> _order = const [];
  int? _sortCol;
  bool _ascending = true;
  int _matches = 0;

  @override
  void initState() {
    super.initState();
    _recompute();
  }

  @override
  void dispose() {
    _h.dispose();
    _v.dispose();
    super.dispose();
  }

  @override
  void didUpdateWidget(ResultTableView old) {
    super.didUpdateWidget(old);
    if (!identical(old.table, widget.table)) {
      _widths = null;
      _sortCol = null;
      _ascending = true;
      if (_v.hasClients) _v.jumpTo(0);
      if (_h.hasClients) _h.jumpTo(0);
      _recompute();
    } else if (old.filter != widget.filter) {
      _recompute();
    }
  }

  /// The row indexes to show: filtered, then sorted.
  void _recompute() {
    final t = widget.table;
    final ordered = _sortCol == null
        ? List<int>.generate(t.rowCount, (i) => i)
        : t.sortOrder(_sortCol!, ascending: _ascending);
    if (widget.filter.trim().isEmpty) {
      _order = ordered;
    } else {
      final keep = t.matchingRows(widget.filter).toSet();
      _order = [
        for (final i in ordered)
          if (keep.contains(i)) i,
      ];
    }
    _matches = _order.length;
  }

  void _sortBy(int col) {
    setState(() {
      if (_sortCol != col) {
        _sortCol = col;
        _ascending = true;
      } else if (_ascending) {
        _ascending = false;
      } else {
        _sortCol = null;
        _ascending = true;
      }
      _recompute();
    });
  }

  bool get _touch => switch (defaultTargetPlatform) {
    TargetPlatform.android ||
    TargetPlatform.iOS ||
    TargetPlatform.fuchsia => true,
    _ => false,
  };

  TextStyle _cellStyle(BuildContext context) =>
      (Theme.of(context).textTheme.bodyMedium ?? const TextStyle()).copyWith(
        fontSize: 13,
      );

  /// Width that fits a column's name and a sample of its cells.
  double _fit(BuildContext context, int col, TextStyle style) {
    final t = widget.table;
    final scaler = MediaQuery.textScalerOf(context);
    double measure(String s, TextStyle st) {
      final p = TextPainter(
        text: TextSpan(text: s, style: st),
        textDirection: TextDirection.ltr,
        textScaler: scaler,
        maxLines: 1,
      )..layout();
      final w = p.width;
      p.dispose();
      return w;
    }

    final head = style.copyWith(fontWeight: FontWeight.w600);
    final small = style.copyWith(fontSize: 11);
    // Room for the sort arrow beside the name and the type under it.
    var w =
        math.max(
          measure(t.columns[col].name, head),
          measure(_typeName(context, t.columns[col].type), small),
        ) +
        24 +
        20;
    // Fewer rows are sampled when there are many columns, so a wide result
    // does not make the first build slow.
    final sample = math.min(t.rowCount, math.max(20, 4000 ~/ t.columnCount));
    for (var r = 0; r < sample; r++) {
      final text = _shown(t.rows[r][col]);
      final cut = text.length > 80 ? text.substring(0, 80) : text;
      // A few pixels of slack: text measures a little differently when laid
      // out in a cell, and an exact fit would show an ellipsis.
      w = math.max(w, measure(cut, style) + 24 + 8);
    }
    return w.clamp(ResultTableView._fitMin, ResultTableView._fitMax);
  }

  String _shown(Object? v) {
    final s = v == null ? '' : cellPreview(v);
    return s.length > ResultTable.maxCellChars
        ? s.substring(0, ResultTable.maxCellChars)
        : s;
  }

  List<double> _initialWidths(BuildContext context, TextStyle style) => [
    for (var c = 0; c < widget.table.columnCount; c++) _fit(context, c, style),
  ];

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final style = _cellStyle(context);
    _widths ??= _initialWidths(context, style);
    final widths = _widths!;

    final scale = MediaQuery.textScalerOf(context).scale(13) / 13;
    final rowHeight = math.max(_touch ? 48.0 : 32.0, 13 * scale * 1.9);
    final headerHeight = math.max(_touch ? 56.0 : 44.0, 13 * scale * 2.9);
    final contentWidth =
        ResultTableView._rowNumberWidth +
        widths.fold<double>(0, (a, b) => a + b);
    final shown = math.min(_order.length, ResultTable.maxGridRows);

    // Code, JSON and numbers read left to right even in a right-to-left app.
    return Directionality(
      textDirection: TextDirection.ltr,
      child: Column(
        key: const Key('result-table'),
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Expanded(
            child: Scrollbar(
              controller: _v,
              notificationPredicate: (n) => n.metrics.axis == Axis.vertical,
              child: LayoutBuilder(
                builder: (context, c) => Scrollbar(
                  controller: _h,
                  thumbVisibility: contentWidth > c.maxWidth,
                  notificationPredicate: (n) =>
                      n.metrics.axis == Axis.horizontal,
                  child: SingleChildScrollView(
                    controller: _h,
                    scrollDirection: Axis.horizontal,
                    child: SizedBox(
                      width: math.max(contentWidth, c.maxWidth),
                      child: Column(
                        children: [
                          _header(context, widths, headerHeight, scheme),
                          Expanded(
                            child: ListView.builder(
                              key: const Key('result-table-body'),
                              controller: _v,
                              physics: const ClampingScrollPhysics(),
                              itemExtent: rowHeight,
                              itemCount: shown,
                              itemBuilder: (context, row) => _row(
                                context,
                                row,
                                _order[row],
                                widths,
                                rowHeight,
                                style,
                                scheme,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
          _footer(context, scheme),
        ],
      ),
    );
  }

  Widget _header(
    BuildContext context,
    List<double> widths,
    double height,
    ColorScheme scheme,
  ) {
    final t = widget.table;
    final l10n = context.l10n;
    final small = Theme.of(context).textTheme.bodySmall
        ?.copyWith(color: scheme.outline, fontSize: 11);
    final bold = _cellStyle(context).copyWith(fontWeight: FontWeight.w600);
    return Container(
      height: height,
      decoration: BoxDecoration(
        color: scheme.surfaceContainerHigh,
        border: Border(bottom: BorderSide(color: scheme.outlineVariant)),
      ),
      child: Stack(
        children: [
          Row(
            children: [
              const SizedBox(width: ResultTableView._rowNumberWidth),
              for (var c = 0; c < t.columnCount; c++)
                SizedBox(
                  key: ValueKey('table-header-$c'),
                  width: widths[c],
                  child: Stack(
                    children: [
                      Positioned.fill(
                        child: Tooltip(
                          message: l10n.tableSortBy(t.columns[c].name),
                          child: InkWell(
                            key: ValueKey('table-sort-$c'),
                            onTap: () => _sortBy(c),
                            child: Padding(
                              padding: const EdgeInsets.fromLTRB(12, 4, 12, 4),
                              child: Row(
                                children: [
                                  Expanded(
                                    child: Column(
                                      mainAxisAlignment:
                                          MainAxisAlignment.center,
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          t.columns[c].name,
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                          style: bold,
                                        ),
                                        Text(
                                          _typeName(context, t.columns[c].type),
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                          style: small,
                                        ),
                                      ],
                                    ),
                                  ),
                                  if (_sortCol == c)
                                    Icon(
                                      _ascending
                                          ? Icons.arrow_upward
                                          : Icons.arrow_downward,
                                      key: Key(
                                        _ascending
                                            ? 'table-sort-asc-$c'
                                            : 'table-sort-desc-$c',
                                      ),
                                      size: 16,
                                    ),
                                ],
                              ),
                            ),
                          ),
                        ),
                      ),
                      // Drag to resize; double-tap to fit the content.
                      Positioned(
                        top: 0,
                        bottom: 0,
                        right: 0,
                        width: 12,
                        child: Semantics(
                          label: l10n.tableResizeColumn(t.columns[c].name),
                          child: GestureDetector(
                            key: ValueKey('table-resize-$c'),
                            behavior: HitTestBehavior.opaque,
                            onHorizontalDragUpdate: (d) => setState(() {
                              widths[c] = (widths[c] + d.delta.dx).clamp(
                                ResultTableView.minColumnWidth,
                                ResultTableView.maxColumnWidth,
                              );
                            }),
                            onDoubleTap: () => setState(
                              () => widths[c] = _fit(
                                context,
                                c,
                                _cellStyle(context),
                              ),
                            ),
                            child: MouseRegion(
                              cursor: SystemMouseCursors.resizeColumn,
                              child: Align(
                                alignment: Alignment.centerRight,
                                child: Container(
                                  width: 1,
                                  color: scheme.outlineVariant,
                                ),
                              ),
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
            ],
          ),
          // The row-number corner stays at the left edge while columns scroll.
          _pinned(
            height,
            Container(
              color: scheme.surfaceContainerHigh,
              alignment: Alignment.center,
              child: Text(
                '#',
                style: small,
                semanticsLabel: l10n.tableRowNumber,
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// [child] held at the left edge of the horizontal scroller.
  Widget _pinned(double height, Widget child) => AnimatedBuilder(
    animation: _h,
    builder: (context, child) => Positioned(
      left: _h.hasClients ? _h.offset : 0,
      top: 0,
      width: ResultTableView._rowNumberWidth,
      height: height,
      child: child!,
    ),
    child: child,
  );

  Widget _row(
    BuildContext context,
    int position,
    int index,
    List<double> widths,
    double height,
    TextStyle style,
    ColorScheme scheme,
  ) {
    final t = widget.table;
    final row = t.rows[index];
    final muted = style.copyWith(
      color: scheme.outline,
      fontStyle: FontStyle.italic,
    );
    return Container(
      key: ValueKey('table-row-$position'),
      height: height,
      decoration: BoxDecoration(
        border: Border(bottom: BorderSide(color: scheme.outlineVariant)),
      ),
      child: Stack(
        children: [
          Row(
            children: [
              const SizedBox(width: ResultTableView._rowNumberWidth),
              for (var c = 0; c < t.columnCount; c++)
                _cell(
                  context,
                  position,
                  c,
                  row[c],
                  widths[c],
                  style,
                  muted,
                  scheme,
                ),
            ],
          ),
          _pinned(
            height,
            Container(
              color: scheme.surfaceContainerLow,
              alignment: Alignment.centerRight,
              padding: const EdgeInsets.only(right: 10),
              child: Text(
                '${index + 1}',
                style: style.copyWith(
                  color: scheme.outline,
                  fontSize: 11,
                  fontFeatures: kTabularFigures,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _cell(
    BuildContext context,
    int row,
    int col,
    Object? value,
    double width,
    TextStyle style,
    TextStyle muted,
    ColorScheme scheme,
  ) {
    final type = widget.table.columns[col].type;
    final numeric = type == ColumnType.number && value is num;
    final Widget text = value == null
        ? Text(
            context.l10n.tableNull,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: muted,
          )
        : Text(
            _shown(value),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: numeric
                ? style.copyWith(fontFeatures: kTabularFigures)
                : (value is Map || value is List)
                ? style.copyWith(
                    color: scheme.onSurfaceVariant,
                    fontFamily: kMonoFamily,
                    fontSize: 12,
                  )
                : style,
          );
    return Container(
      key: ValueKey('table-cell-$row-$col'),
      width: width,
      padding: const EdgeInsets.symmetric(horizontal: 12),
      alignment: numeric ? Alignment.centerRight : Alignment.centerLeft,
      decoration: BoxDecoration(
        border: Border(right: BorderSide(color: scheme.outlineVariant)),
      ),
      child: text,
    );
  }

  Widget _footer(BuildContext context, ColorScheme scheme) {
    final t = widget.table;
    final l10n = context.l10n;
    final filtered = _matches != t.rowCount;
    final parts = <String>[
      filtered
          ? l10n.tableFiltered(_matches, t.rowCount)
          : l10n.tableSummary(t.rowCount, t.columnCount),
      if (filtered) l10n.tableColumns(t.columnCount),
      if (_matches > ResultTable.maxGridRows)
        l10n.tableCapped(ResultTable.maxGridRows),
      if (t.columnsDropped > 0) l10n.tableColumnsDropped(t.columnsDropped),
    ];
    return Container(
      key: const Key('table-footer'),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        border: Border(top: BorderSide(color: scheme.outlineVariant)),
      ),
      child: Text(
        parts.join(' · '),
        style: Theme.of(context).textTheme.bodySmall
            ?.copyWith(color: scheme.onSurfaceVariant),
      ),
    );
  }

  String _typeName(BuildContext context, ColumnType type) {
    final l10n = context.l10n;
    return switch (type) {
      ColumnType.text => l10n.tableTypeText,
      ColumnType.number => l10n.tableTypeNumber,
      ColumnType.boolean => l10n.tableTypeBoolean,
      ColumnType.date => l10n.tableTypeDate,
      ColumnType.json => l10n.tableTypeJson,
      ColumnType.empty => l10n.tableTypeEmpty,
    };
  }
}
