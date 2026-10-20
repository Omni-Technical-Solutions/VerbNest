import 'dart:math' as math;

import 'ui/still_scrollbar.dart';

import 'package:flutter/foundation.dart'
    show TargetPlatform, defaultTargetPlatform;
import 'package:flutter/gestures.dart' show PointerDeviceKind, kPrimaryButton;
import 'package:flutter/services.dart';
import 'package:material_ui/material_ui.dart';
import 'package:verbnest_core/verbnest_core.dart';

import '../../l10n/l10n.dart';
import '../theme.dart';
import 'ui/adaptive_dialog.dart';
import 'ui/toast.dart';
import 'ui/still_tooltip.dart';
import 'result_table_selection.dart';
import 'result_table_sizing.dart';

/// A read-only grid of a [ResultTable], in the manner of a database client's
/// results grid (FR-RES-008, FR-RES-009): the header and the row numbers stay
/// in view while the rest scrolls, columns resize by dragging the header's
/// edge (double-tap fits the content), a header tap sorts, and a footer counts
/// rows.
///
/// Select a cell by clicking it (Shift extends, dragging with a mouse selects a
/// range, the arrow keys move), a row by its number, everything from the corner.
/// Cmd/Ctrl+C copies the selection as tab-separated text; the menu copies as
/// CSV, JSON or Markdown and saves CSV. Enter or a double click shows a value in
/// full; on a touch screen a tap does.
///
/// Rows are fixed height and built lazily, so a result of tens of thousands of
/// rows scrolls without building them all.
class ResultTableView extends StatefulWidget {
  const ResultTableView({
    super.key,
    required this.table,
    this.filter = '',
    this.leading,
    this.onSaveCsv,
  });

  final ResultTable table;

  /// Only rows with a cell containing this text (case-insensitive) show.
  final String filter;

  /// Shown at the start of the bar above the grid (the owner's own choices).
  final Widget? leading;

  /// Saves the CSV text of the rows shown; the menu item shows only when set.
  final Future<void> Function(String csv)? onSaveCsv;

  static const minColumnWidth = 60.0;
  static const maxColumnWidth = 800.0;
  static const _rowNumberWidth = 56.0;

  @override
  State<ResultTableView> createState() => _ResultTableViewState();
}

enum _Format { tsv, csv, json, markdown }

class _ResultTableViewState extends State<ResultTableView> {
  final _h = ScrollController();
  final _v = ScrollController();
  final _focus = FocusNode(debugLabel: 'result table');
  List<double>? _widths;
  List<int> _order = const [];
  int? _sortCol;
  bool _ascending = true;
  int _matches = 0;

  final _sel = TableSelection();
  bool _dragging = false;

  // The last mouse click, to tell a double click without a gesture recogniser
  // (which would hold every click back and leave a timer running).
  Duration? _lastClickAt;
  ({int row, int col})? _lastClickCell;

  // From the last build, to turn a pointer position into a cell.
  double _rowHeight = 32;
  double _viewHeight = 0;
  double _viewWidth = 0;

  int get _shown => math.min(_order.length, ResultTable.maxGridRows);

  /// Columns drawn. The rest are still in the table for search, copy and export.
  int get _cols => math.min(widget.table.columnCount, ResultTable.maxColumns);

  /// A controller's offset, or 0 when it has no view (or, for an instant while
  /// the grid is rebuilt, more than one).
  double _offset(ScrollController c) =>
      c.hasClients && c.positions.length == 1 ? c.offset : 0;

  @override
  void initState() {
    super.initState();
    _recompute();
  }

  @override
  void dispose() {
    _h.dispose();
    _v.dispose();
    _focus.dispose();
    super.dispose();
  }

  @override
  void didUpdateWidget(ResultTableView old) {
    super.didUpdateWidget(old);
    if (!identical(old.table, widget.table)) {
      _widths = null;
      _sortCol = null;
      _ascending = true;
      _clearSelection();
      if (_v.hasClients) _v.jumpTo(0);
      if (_h.hasClients) _h.jumpTo(0);
      _recompute();
    } else if (old.filter != widget.filter) {
      _clearSelection();
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
      _clearSelection();
      _recompute();
    });
  }

  bool get _touch => switch (defaultTargetPlatform) {
    TargetPlatform.android ||
    TargetPlatform.iOS ||
    TargetPlatform.fuchsia => true,
    _ => false,
  };

  // ------------------------------------------------------------ selection

  void _clearSelection() => _sel.clear();

  bool get _hasSelection => _sel.hasSelection;

  ({int r0, int r1, int c0, int c1})? get _range =>
      _sel.range(shown: _shown, cols: _cols);

  bool _isSelected(int r, int c) =>
      _sel.isSelected(r, c, shown: _shown, cols: _cols);

  bool _isFocus(int r, int c) => _sel.isFocus(r, c);

  int get _selectedCount => _sel.selectedCount(
    shown: _shown,
    cols: _cols,
    totalRows: _order.length,
    totalCols: widget.table.columnCount,
  );

  void _selectCell(int r, int c, {bool extend = false}) =>
      setState(() => _sel.selectCell(r, c, extend: extend));

  void _selectRow(int r, {bool extend = false}) =>
      setState(() => _sel.selectRow(r, extend: extend));

  void _selectColumn(int c) {
    setState(() => _sel.selectColumn(c));
    _focus.requestFocus();
  }

  void _selectAll() {
    if (_shown == 0) return;
    setState(_sel.selectAll);
    _focus.requestFocus();
  }

  /// The row and column under a pointer inside the body; a column of -1 is the
  /// row-number column.
  ({int row, int col})? _cellAt(Offset p) {
    final r = ((p.dy + (_offset(_v))) / _rowHeight).floor();
    if (r < 0 || r >= _shown) return null;
    final hx = _offset(_h);
    if (p.dx - hx < ResultTableView._rowNumberWidth) return (row: r, col: -1);
    var x = p.dx - ResultTableView._rowNumberWidth;
    final widths = _widths;
    if (widths == null) return null;
    for (var c = 0; c < widths.length; c++) {
      if (x < widths[c]) return (row: r, col: c);
      x -= widths[c];
    }
    return null;
  }

  void _pointerDown(PointerDownEvent e) {
    if (e.kind != PointerDeviceKind.mouse || e.buttons != kPrimaryButton) {
      return;
    }
    final cell = _cellAt(e.localPosition);
    _focus.requestFocus();
    if (cell == null) return;
    final shift = HardwareKeyboard.instance.isShiftPressed;
    if (cell.col < 0) {
      _selectRow(cell.row, extend: shift);
    } else {
      final double =
          _lastClickCell == cell &&
          _lastClickAt != null &&
          e.timeStamp - _lastClickAt! < const Duration(milliseconds: 400);
      _lastClickAt = double ? null : e.timeStamp;
      _lastClickCell = double ? null : cell;
      _selectCell(cell.row, cell.col, extend: shift);
      if (double) {
        _showValue(cell.row, cell.col);
      } else {
        _dragging = true;
      }
    }
  }

  void _pointerMove(PointerMoveEvent e) {
    if (!_dragging || e.kind != PointerDeviceKind.mouse) return;
    final cell = _cellAt(e.localPosition);
    if (cell == null || cell.col < 0) return;
    if (cell.row != _sel.fr || cell.col != _sel.fc) {
      setState(() {
        _sel.fr = cell.row;
        _sel.fc = cell.col;
      });
    }
  }

  void _pointerUp(PointerEvent e) => _dragging = false;

  void _touchTap(TapDownDetails d) {
    // A touch screen has no hover or selection handles: a tap shows the value.
    if (d.kind == PointerDeviceKind.mouse) return;
    final cell = _cellAt(d.localPosition);
    if (cell == null || cell.col < 0) return;
    _selectCell(cell.row, cell.col);
    _showValue(cell.row, cell.col);
  }

  // ---------------------------------------------------------------- keys

  KeyEventResult _onKey(FocusNode node, KeyEvent e) {
    if (e is! KeyDownEvent && e is! KeyRepeatEvent) {
      return KeyEventResult.ignored;
    }
    final key = e.logicalKey;
    final kb = HardwareKeyboard.instance;
    final cmd = kb.isMetaPressed || kb.isControlPressed;
    if (cmd && key == LogicalKeyboardKey.keyC) {
      _copy(_Format.tsv);
      return KeyEventResult.handled;
    }
    if (cmd && key == LogicalKeyboardKey.keyA) {
      _selectAll();
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.escape) {
      if (!_hasSelection) return KeyEventResult.ignored;
      setState(_clearSelection);
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.enter ||
        key == LogicalKeyboardKey.numpadEnter) {
      if (_sel.fr == null ||
          _sel.fc == null ||
          _sel.wholeRows ||
          _sel.wholeCols) {
        return KeyEventResult.ignored;
      }
      _showValue(_sel.fr!, _sel.fc!);
      return KeyEventResult.handled;
    }
    final page = math.max(1, (_viewHeight / _rowHeight).floor() - 2);
    final cols = _cols;
    var dr = 0, dc = 0;
    if (key == LogicalKeyboardKey.arrowDown) dr = 1;
    if (key == LogicalKeyboardKey.arrowUp) dr = -1;
    if (key == LogicalKeyboardKey.arrowRight) dc = 1;
    if (key == LogicalKeyboardKey.arrowLeft) dc = -1;
    if (key == LogicalKeyboardKey.pageDown) dr = page;
    if (key == LogicalKeyboardKey.pageUp) dr = -page;
    if (key == LogicalKeyboardKey.home) dc = -cols;
    if (key == LogicalKeyboardKey.end) dc = cols;
    if ((dr == 0 && dc == 0) || _shown == 0) return KeyEventResult.ignored;
    final r = ((_sel.fr ?? 0) + (_hasSelection ? dr : 0)).clamp(0, _shown - 1);
    final c = ((_sel.fc ?? 0) + (_hasSelection ? dc : 0)).clamp(0, cols - 1);
    _selectCell(r, c, extend: kb.isShiftPressed);
    _reveal(r, c);
    return KeyEventResult.handled;
  }

  /// Scrolls so that the cell at [r], [c] is in view.
  void _reveal(int r, int c) {
    if (_v.hasClients) {
      final top = r * _rowHeight;
      final bottom = top + _rowHeight;
      final off = _v.offset;
      if (top < off) {
        _v.jumpTo(top);
      } else if (bottom > off + _viewHeight) {
        _v.jumpTo(bottom - _viewHeight);
      }
    }
    final widths = _widths;
    if (_h.hasClients && widths != null) {
      var left = ResultTableView._rowNumberWidth;
      for (var i = 0; i < c; i++) {
        left += widths[i];
      }
      final right = left + widths[c];
      final off = _h.offset;
      // The row numbers cover the first 56 dp of the view.
      if (left < off + ResultTableView._rowNumberWidth) {
        _h.jumpTo(math.max(0, left - ResultTableView._rowNumberWidth));
      } else if (right > off + _viewWidth) {
        _h.jumpTo(right - _viewWidth);
      }
    }
  }

  // ---------------------------------------------------------------- copy

  /// Copies the selection (or, with none, every row shown) in [format].
  void _copy(_Format format, {bool header = false}) {
    final t = widget.table;
    final g = _range;
    // A whole column takes every row, a whole row every column (also those the
    // grid does not draw); a range takes just its cells.
    final rows = g == null || _sel.wholeCols
        ? _order
        : [for (var r = g.r0; r <= g.r1; r++) _order[r]];
    final cols = g == null || _sel.wholeRows
        ? List<int>.generate(t.columnCount, (i) => i)
        : [for (var c = g.c0; c <= g.c1; c++) c];
    if (rows.isEmpty) return;
    final text = switch (format) {
      _Format.tsv => t.toTsv(rows, cols, header: header),
      _Format.csv => t.toCsv(rows, cols),
      _Format.json => t.toJson(rows, cols),
      _Format.markdown => t.toMarkdown(rows, cols),
    };
    Clipboard.setData(ClipboardData(text: text));
    showToast(context, context.l10n.tableCopied(rows.length * cols.length));
  }

  Future<void> _saveCsv() async {
    final save = widget.onSaveCsv;
    if (save == null) return;
    final t = widget.table;
    await save(t.toCsv(_order, List<int>.generate(t.columnCount, (i) => i)));
  }

  void _showValue(int row, int col) {
    final t = widget.table;
    final value = t.rows[_order[row]][col];
    final l10n = context.l10n;
    showDetail(
      context,
      title: t.columns[col].name,
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

  List<PopupMenuEntry<String>> _menuEntries({int? column}) {
    final l10n = context.l10n;
    return [
      PopupMenuItem(
        key: const Key('menu-copy-cells'),
        value: 'copy',
        enabled: _hasSelection,
        child: Text(l10n.tableCopy),
      ),
      PopupMenuItem(
        key: const Key('menu-copy-headers'),
        value: 'copy-headers',
        enabled: _hasSelection,
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
        if (_sortCol == column)
          PopupMenuItem(
            key: const Key('menu-clear-sort'),
            value: 'clear-sort',
            child: Text(l10n.tableClearSort),
          ),
      ],
      if (_hasSelection && !_sel.wholeRows && !_sel.wholeCols)
        PopupMenuItem(
          key: const Key('menu-view-value'),
          value: 'view',
          child: Text(l10n.tableViewValue),
        ),
      if (widget.onSaveCsv != null) ...[
        const PopupMenuDivider(),
        PopupMenuItem(
          key: const Key('menu-save-csv'),
          value: 'save',
          child: Text(l10n.tableSaveCsv),
        ),
      ],
    ];
  }

  void _onMenu(String v) {
    if (v == 'copy') return _copy(_Format.tsv);
    if (v == 'copy-headers') return _copy(_Format.tsv, header: true);
    if (v == 'csv') return _copy(_Format.csv);
    if (v == 'json') return _copy(_Format.json);
    if (v == 'markdown') return _copy(_Format.markdown);
    if (v == 'all') return _selectAll();
    if (v == 'save') {
      _saveCsv();
    } else if (v == 'view' && _sel.fr != null && _sel.fc != null) {
      _showValue(_sel.fr!, _sel.fc!);
    } else if (v == 'clear-sort') {
      setState(() {
        _sortCol = null;
        _clearSelection();
        _recompute();
      });
    } else if (v.startsWith('column:')) {
      _selectColumn(int.parse(v.substring(7)));
    } else if (v.startsWith('fit:')) {
      final c = int.parse(v.substring(4));
      setState(() => _widths![c] = _fit(context, c, _cellStyle(context)));
    }
  }

  Future<void> _menuAt(Offset global, {int? column}) async {
    final overlay =
        Overlay.of(context).context.findRenderObject()! as RenderBox;
    final v = await showMenu<String>(
      popUpAnimationStyle: AnimationStyle.noAnimation,
      context: context,
      position: RelativeRect.fromRect(
        Rect.fromPoints(global, global),
        Offset.zero & overlay.size,
      ),
      items: _menuEntries(column: column),
    );
    if (v != null && mounted) _onMenu(v);
  }

  void _bodyMenu(Offset local, Offset global) {
    final cell = _cellAt(local);
    if (cell == null) return;
    // A right click on a cell outside the selection selects it first.
    if (cell.col >= 0 && !_isSelected(cell.row, cell.col)) {
      _selectCell(cell.row, cell.col);
    } else if (cell.col < 0) {
      _selectRow(cell.row);
    }
    _menuAt(global);
  }

  // ------------------------------------------------------------- measure

  TextStyle _cellStyle(BuildContext context) =>
      (Theme.of(context).textTheme.bodyMedium ?? const TextStyle()).copyWith(
        fontSize: 13,
      );

  /// Width that fits a column's name and a sample of its cells.
  double _fit(BuildContext context, int col, TextStyle style) =>
      TableColumnSizer.fit(
        table: widget.table,
        col: col,
        drawn: _cols,
        style: style,
        scaler: MediaQuery.textScalerOf(context),
        typeName: (type) => _typeName(context, type),
      );

  String _shownText(Object? v) => TableColumnSizer.shownText(v);

  List<double> _initialWidths(BuildContext context, TextStyle style) => [
    for (var c = 0; c < _cols; c++) _fit(context, c, style),
  ];

  // --------------------------------------------------------------- build

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final style = _cellStyle(context);
    _widths ??= _initialWidths(context, style);
    final widths = _widths!;

    final scale = MediaQuery.textScalerOf(context).scale(13) / 13;
    // Whole pixels throughout, so rows, rules and text never land between
    // pixels (which draws them soft).
    final rowHeight = math
        .max(_touch ? 48.0 : 32.0, 13 * scale * 1.9)
        .roundToDouble();
    final headerHeight = math
        .max(_touch ? 56.0 : 44.0, 13 * scale * 2.9)
        .roundToDouble();
    _rowHeight = rowHeight;
    final contentWidth =
        ResultTableView._rowNumberWidth +
        widths.fold<double>(0, (a, b) => a + b);

    // Code, JSON and numbers read left to right even in a right-to-left app.
    return Directionality(
      textDirection: TextDirection.ltr,
      child: Focus(
        focusNode: _focus,
        onKeyEvent: _onKey,
        // A short pane (a landscape phone, large text) scrolls instead of
        // overflowing: the bar, the header and the footer need about this much.
        // The scroll view is always there (it simply does not scroll when the
        // grid fits), so the table is never rebuilt as the pane crosses the
        // limit, and sort and selection survive the keyboard coming and going.
        child: LayoutBuilder(
          builder: (context, outer) {
            final textScale = MediaQuery.textScalerOf(context).scale(1);
            final needed =
                200 * (textScale <= 1 ? 1.0 : textScale * math.sqrt(textScale));
            final fixed = outer.hasBoundedHeight
                ? math.max(outer.maxHeight, needed)
                : needed;
            return SingleChildScrollView(
              keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
              child: SizedBox(
                height: fixed,
                child: _grid(
                  context,
                  widths,
                  rowHeight,
                  headerHeight,
                  contentWidth,
                  style,
                  scheme,
                ),
              ),
            );
          },
        ),
      ),
    );
  }

  Widget _grid(
    BuildContext context,
    List<double> widths,
    double rowHeight,
    double headerHeight,
    double contentWidth,
    TextStyle style,
    ColorScheme scheme,
  ) {
    return Column(
      key: const Key('result-table'),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _bar(context),
        Expanded(
          child: StillScrollbar(
            controller: _v,
            notificationPredicate: (n) => n.metrics.axis == Axis.vertical,
            child: LayoutBuilder(
              builder: (context, c) {
                _viewHeight = math.max(0, c.maxHeight - headerHeight);
                _viewWidth = c.maxWidth;
                return StillScrollbar(
                  controller: _h,
                  thumbVisibility: contentWidth > c.maxWidth,
                  axis: Axis.horizontal,
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
                            child: _body(widths, rowHeight, style, scheme),
                          ),
                        ],
                      ),
                    ),
                  ),
                );
              },
            ),
          ),
        ),
        _footer(context, scheme),
      ],
    );
  }

  Widget _body(
    List<double> widths,
    double rowHeight,
    TextStyle style,
    ColorScheme scheme,
  ) => Listener(
    onPointerDown: _pointerDown,
    onPointerMove: _pointerMove,
    onPointerUp: _pointerUp,
    onPointerCancel: _pointerUp,
    child: GestureDetector(
      behavior: HitTestBehavior.translucent,
      // The cells carry their own semantics; one big unlabeled tap target over
      // the whole grid would confuse a screen reader.
      excludeFromSemantics: true,
      onTapDown: _touchTap,
      onSecondaryTapDown: (d) => _bodyMenu(d.localPosition, d.globalPosition),
      onLongPressStart: (d) {
        if (_touch) _bodyMenu(d.localPosition, d.globalPosition);
      },
      child: ListView.builder(
        key: const Key('result-table-body'),
        controller: _v,
        physics: const ClampingScrollPhysics(),
        itemExtent: rowHeight,
        itemCount: _shown,
        itemBuilder: (context, row) =>
            _row(context, row, _order[row], widths, rowHeight, style, scheme),
      ),
    ),
  );

  /// The owner's choices (rows from, flatten, header row), above the grid; no
  /// bar at all when there are none, so the rows get the room.
  Widget _bar(BuildContext context) => widget.leading == null
      ? const SizedBox.shrink()
      : Padding(
          padding: const EdgeInsets.fromLTRB(8, 0, 8, 0),
          child: Align(
            alignment: AlignmentDirectional.centerStart,
            child: widget.leading,
          ),
        );

  Widget _header(
    BuildContext context,
    List<double> widths,
    double height,
    ColorScheme scheme,
  ) {
    final l10n = context.l10n;
    final small = Theme.of(context).textTheme.bodySmall
        ?.copyWith(color: scheme.outline, fontSize: 11);
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
              for (var c = 0; c < _cols; c++)
                SizedBox(
                  key: ValueKey('table-header-$c'),
                  width: widths[c],
                  child: Stack(
                    children: [
                      _headerLabel(context, c),
                      _resizeHandle(context, c, widths, scheme),
                    ],
                  ),
                ),
            ],
          ),
          // The corner selects everything and stays at the left edge while
          // the columns scroll.
          _pinned(
            height,
            InkWell(
              key: const Key('table-select-all'),
              onTap: _selectAll,
              child: Container(
                color: scheme.surfaceContainerHigh,
                alignment: Alignment.center,
                child: Text(
                  '#',
                  style: small,
                  semanticsLabel: l10n.tableRowNumber,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// The name and type of column [c], tappable to sort, with its menu.
  Widget _headerLabel(BuildContext context, int c) {
    final t = widget.table;
    final l10n = context.l10n;
    final scheme = Theme.of(context).colorScheme;
    final small = Theme.of(context).textTheme.bodySmall
        ?.copyWith(color: scheme.outline, fontSize: 11);
    final bold = _cellStyle(context).copyWith(fontWeight: FontWeight.w600);
    return Positioned.fill(
      child: StillTooltip(
        message: l10n.tableSortBy(t.columns[c].name),
        child: Semantics(
          button: true,
          label: l10n.tableHeaderLabel(
            t.columns[c].name,
            _typeName(context, t.columns[c].type),
          ),
          value: _sortCol != c
              ? null
              : (_ascending
                    ? l10n.tableSortedAscending
                    : l10n.tableSortedDescending),
          onTap: () => _sortBy(c),
          excludeSemantics: true,
          child: GestureDetector(
            excludeFromSemantics: true,
            onSecondaryTapDown: (d) => _menuAt(d.globalPosition, column: c),
            onLongPressStart: (d) => _menuAt(d.globalPosition, column: c),
            child: InkWell(
              key: ValueKey('table-sort-$c'),
              onTap: () => _sortBy(c),
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
                        _ascending ? Icons.arrow_upward : Icons.arrow_downward,
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
      ),
    );
  }

  /// Drag to resize; double-tap to fit the content.
  Widget _resizeHandle(
    BuildContext context,
    int c,
    List<double> widths,
    ColorScheme scheme,
  ) {
    return Positioned(
      top: 0,
      bottom: 0,
      right: 0,
      width: 12,
      // Out of the accessibility tree: it is a 12 dp drag handle,
      // and "Fit column" is in the header menu.
      child: ExcludeSemantics(
        child: GestureDetector(
          key: ValueKey('table-resize-$c'),
          behavior: HitTestBehavior.opaque,
          onHorizontalDragUpdate: (d) => setState(() {
            widths[c] = (widths[c] + d.delta.dx)
                .clamp(
                  ResultTableView.minColumnWidth,
                  ResultTableView.maxColumnWidth,
                )
                .roundToDouble();
          }),
          onDoubleTap: () =>
              setState(() => widths[c] = _fit(context, c, _cellStyle(context))),
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

  /// [child] held at the left edge of the horizontal scroller.
  Widget _pinned(double height, Widget child) => AnimatedBuilder(
    animation: _h,
    builder: (context, child) => Positioned(
      left: _offset(_h),
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
    final g = _range;
    final rowSelected = g != null && position >= g.r0 && position <= g.r1;
    // The row's rule is drawn by each cell, so a cell is the full row height
    // (a 1 dp border on the row would leave its tap target 47 dp).
    return SizedBox(
      key: ValueKey('table-row-$position'),
      height: height,
      child: Stack(
        children: [
          Row(
            children: [
              const SizedBox(width: ResultTableView._rowNumberWidth),
              for (var c = 0; c < _cols; c++)
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
            Semantics(
              label: context.l10n.tableRowLabel(index + 1),
              selected: rowSelected,
              onTap: () => _selectRow(position),
              excludeSemantics: true,
              child: Container(
                decoration: BoxDecoration(
                  color: rowSelected
                      ? scheme.secondaryContainer
                      : scheme.surfaceContainerLow,
                  border: Border(
                    bottom: BorderSide(color: scheme.outlineVariant),
                  ),
                ),
                alignment: Alignment.centerRight,
                padding: const EdgeInsets.only(right: 10),
                child: Text(
                  '${index + 1}',
                  style: style.copyWith(
                    color: rowSelected
                        ? scheme.onSecondaryContainer
                        : scheme.outline,
                    fontSize: 11,
                    fontFeatures: kTabularFigures,
                  ),
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
    final selected = _isSelected(row, col);
    final Widget text = value == null
        ? Text(
            context.l10n.tableNull,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: muted,
          )
        : Text(
            _shownText(value),
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
    final l10n = context.l10n;
    final spoken = value == null ? l10n.tableNull : cellText(value);
    return Semantics(
      label: l10n.tableCellLabel(
        widget.table.columns[col].name,
        row + 1,
        _matches,
        spoken.length > 200 ? spoken.substring(0, 200) : spoken,
      ),
      selected: selected,
      // A screen reader activates a cell to see its value in full.
      onTap: () {
        _selectCell(row, col);
        _showValue(row, col);
      },
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
        foregroundDecoration: _isFocus(row, col)
            ? BoxDecoration(border: Border.all(color: scheme.primary, width: 2))
            : null,
        child: text,
      ),
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
      if (_selectedCount > 1) l10n.tableSelected(_selectedCount),
    ];
    // The copy and export menu sits at the end of the footer: a bar of its
    // own above the grid would cost every table a row.
    final size = _touch ? 48.0 : 32.0;
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
              onSelected: _onMenu,
              itemBuilder: (context) => _menuEntries(),
            ),
          ),
        ],
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
