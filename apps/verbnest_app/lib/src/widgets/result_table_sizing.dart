import 'dart:math' as math;

import 'package:flutter/widgets.dart';
import 'package:verbnest_core/verbnest_core.dart';

/// How wide the columns of the results table start out: wide enough for a
/// column's name, its type, and a sample of its cells. Widths are whole
/// pixels, so cell edges and text never land between pixels.
class TableColumnSizer {
  const TableColumnSizer._();

  static const fitMin = 80.0;
  static const fitMax = 360.0;

  static double _whole(double w) => w.roundToDouble();

  /// The text a cell shows, cut at [ResultTable.maxCellChars].
  static String shownText(Object? v) {
    final s = v == null ? '' : cellPreview(v);
    return s.length > ResultTable.maxCellChars
        ? s.substring(0, ResultTable.maxCellChars)
        : s;
  }

  /// Width that fits the name, type and a sample of the cells of [col].
  /// [drawn] is how many columns the grid draws (it samples fewer rows when
  /// there are many columns, so a wide result does not make the first build
  /// slow).
  static double fit({
    required ResultTable table,
    required int col,
    required int drawn,
    required TextStyle style,
    required TextScaler scaler,
    required String Function(ColumnType) typeName,
  }) {
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
          measure(table.columns[col].name, head),
          measure(typeName(table.columns[col].type), small),
        ) +
        24 +
        20;
    final sample = math.min(table.rowCount, math.max(20, 4000 ~/ drawn));
    for (var r = 0; r < sample; r++) {
      final text = shownText(table.rows[r][col]);
      final cut = text.length > 80 ? text.substring(0, 80) : text;
      // A few pixels of slack: text measures a little differently when laid
      // out in a cell, and an exact fit would show an ellipsis.
      w = math.max(w, measure(cut, style) + 24 + 8);
    }
    return _whole(w.clamp(fitMin, fitMax));
  }
}
