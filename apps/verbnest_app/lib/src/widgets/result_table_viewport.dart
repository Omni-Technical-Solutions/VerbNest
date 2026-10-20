import 'dart:math' as math;

import 'package:flutter/services.dart';
import 'package:material_ui/material_ui.dart';

/// Where the grid sits on screen: its two scroll positions, column widths
/// and the size of the last build. It turns a pointer position into a cell
/// and scrolls a cell into view.
class TableViewport {
  static const rowNumberWidth = 56.0;

  final h = ScrollController();
  final v = ScrollController();

  /// Null until the first build measures the columns.
  List<double>? widths;

  // From the last build, to turn a pointer position into a cell.
  double rowHeight = 32;
  double height = 0;
  double width = 0;

  void dispose() {
    h.dispose();
    v.dispose();
  }

  void jumpToStart() {
    if (v.hasClients) v.jumpTo(0);
    if (h.hasClients) h.jumpTo(0);
  }

  /// A controller's offset, or 0 when it has no view (or, for an instant while
  /// the grid is rebuilt, more than one).
  double offset(ScrollController c) =>
      c.hasClients && c.positions.length == 1 ? c.offset : 0;

  /// Rows that fit in a page of the view, less two for context.
  int get pageRows => math.max(1, (height / rowHeight).floor() - 2);

  /// The row and column under a pointer inside the body; a column of -1 is the
  /// row-number column.
  ({int row, int col})? cellAt(Offset p, {required int shown}) {
    final r = ((p.dy + offset(v)) / rowHeight).floor();
    if (r < 0 || r >= shown) return null;
    if (p.dx - offset(h) < rowNumberWidth) return (row: r, col: -1);
    var x = p.dx - rowNumberWidth;
    final widths = this.widths;
    if (widths == null) return null;
    for (var c = 0; c < widths.length; c++) {
      if (x < widths[c]) return (row: r, col: c);
      x -= widths[c];
    }
    return null;
  }

  /// Scrolls so that the cell at [r], [c] is in view.
  void reveal(int r, int c) {
    if (v.hasClients) {
      final top = r * rowHeight;
      final bottom = top + rowHeight;
      final off = v.offset;
      if (top < off) {
        v.jumpTo(top);
      } else if (bottom > off + height) {
        v.jumpTo(bottom - height);
      }
    }
    final widths = this.widths;
    if (h.hasClients && widths != null) {
      var left = rowNumberWidth;
      for (var i = 0; i < c; i++) {
        left += widths[i];
      }
      final right = left + widths[c];
      final off = h.offset;
      // The row numbers cover the first 56 dp of the view.
      if (left < off + rowNumberWidth) {
        h.jumpTo(math.max(0, left - rowNumberWidth));
      } else if (right > off + width) {
        h.jumpTo(right - width);
      }
    }
  }
}

/// How an arrow, page, home or end key moves the focused cell: rows down and
/// columns right, or null for any other key.
({int dr, int dc})? tableKeyMove(
  LogicalKeyboardKey key, {
  required int page,
  required int cols,
}) {
  if (key == LogicalKeyboardKey.arrowDown) return (dr: 1, dc: 0);
  if (key == LogicalKeyboardKey.arrowUp) return (dr: -1, dc: 0);
  if (key == LogicalKeyboardKey.arrowRight) return (dr: 0, dc: 1);
  if (key == LogicalKeyboardKey.arrowLeft) return (dr: 0, dc: -1);
  if (key == LogicalKeyboardKey.pageDown) return (dr: page, dc: 0);
  if (key == LogicalKeyboardKey.pageUp) return (dr: -page, dc: 0);
  if (key == LogicalKeyboardKey.home) return (dr: 0, dc: -cols);
  if (key == LogicalKeyboardKey.end) return (dr: 0, dc: cols);
  return null;
}
