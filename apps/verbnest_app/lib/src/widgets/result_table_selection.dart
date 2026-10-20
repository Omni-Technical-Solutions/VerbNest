import 'dart:math' as math;

/// Which cells of the results table are selected: an anchor and a focus cell
/// (row position, column) and whether the selection covers whole rows or whole
/// columns. Pure state with no widgets, so its rules are unit tested directly.
class TableSelection {
  int? ar, ac, fr, fc;
  bool wholeRows = false;
  bool wholeCols = false;

  void clear() {
    ar = ac = fr = fc = null;
    wholeRows = wholeCols = false;
  }

  bool get hasSelection => fr != null;

  /// The selected block of the drawn grid, or null when nothing is selected.
  /// [shown] is the number of rows drawn and [cols] the number of columns.
  ({int r0, int r1, int c0, int c1})? range({
    required int shown,
    required int cols,
  }) {
    if (fr == null || shown == 0) return null;
    var r0 = math.min(ar!, fr!), r1 = math.max(ar!, fr!);
    var c0 = math.min(ac!, fc!), c1 = math.max(ac!, fc!);
    if (wholeRows) {
      c0 = 0;
      c1 = cols - 1;
    }
    if (wholeCols) {
      r0 = 0;
      r1 = shown - 1;
    }
    return (
      r0: r0.clamp(0, shown - 1),
      r1: r1.clamp(0, shown - 1),
      c0: c0.clamp(0, cols - 1),
      c1: c1.clamp(0, cols - 1),
    );
  }

  bool isSelected(int r, int c, {required int shown, required int cols}) {
    final g = range(shown: shown, cols: cols);
    return g != null && r >= g.r0 && r <= g.r1 && c >= g.c0 && c <= g.c1;
  }

  bool isFocus(int r, int c) => fr == r && fc == c && !wholeRows && !wholeCols;

  /// Cells selected. A whole row or column covers the rows and columns that
  /// are not drawn too, as copying it will: [totalRows] and [totalCols] are
  /// the table's, [shown] and [cols] those drawn.
  int selectedCount({
    required int shown,
    required int cols,
    required int totalRows,
    required int totalCols,
  }) {
    final g = range(shown: shown, cols: cols);
    if (g == null) return 0;
    final rows = wholeCols ? totalRows : g.r1 - g.r0 + 1;
    final columns = wholeRows ? totalCols : g.c1 - g.c0 + 1;
    return rows * columns;
  }

  void selectCell(int r, int c, {bool extend = false}) {
    if (extend && hasSelection && !wholeRows && !wholeCols) {
      fr = r;
      fc = c;
    } else {
      ar = fr = r;
      ac = fc = c;
      wholeRows = wholeCols = false;
    }
  }

  void selectRow(int r, {bool extend = false}) {
    if (extend && hasSelection && wholeRows) {
      fr = r;
    } else {
      ar = fr = r;
      ac = fc = 0;
      wholeRows = true;
      wholeCols = false;
    }
  }

  void selectColumn(int c) {
    ar = fr = 0;
    ac = fc = c;
    wholeCols = true;
    wholeRows = false;
  }

  void selectAll() {
    ar = fr = 0;
    ac = fc = 0;
    wholeRows = true;
    wholeCols = true;
  }
}
