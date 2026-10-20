import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:verbnest_app/src/widgets/result_table_viewport.dart';

void main() {
  test('a pointer position becomes a row and column', () {
    final vp = TableViewport()
      ..rowHeight = 30
      ..widths = [100, 50];
    // The first 56 dp are the row numbers.
    expect(vp.cellAt(const Offset(10, 65), shown: 5), (row: 2, col: -1));
    expect(vp.cellAt(const Offset(60, 5), shown: 5), (row: 0, col: 0));
    expect(vp.cellAt(const Offset(56 + 100 + 10, 5), shown: 5), (
      row: 0,
      col: 1,
    ));
    // Past the last column, past the last row, or before measuring.
    expect(vp.cellAt(const Offset(400, 5), shown: 5), isNull);
    expect(vp.cellAt(const Offset(60, 160), shown: 5), isNull);
    vp.widths = null;
    expect(vp.cellAt(const Offset(60, 5), shown: 5), isNull);
    vp.dispose();
  });

  test('page size leaves two rows of context and is at least one', () {
    final vp = TableViewport()
      ..rowHeight = 20
      ..height = 400;
    expect(vp.pageRows, 18);
    vp.height = 10;
    expect(vp.pageRows, 1);
    vp.dispose();
  });

  test('keys move the focused cell', () {
    ({int dr, int dc})? move(LogicalKeyboardKey k) =>
        tableKeyMove(k, page: 10, cols: 6);
    expect(move(LogicalKeyboardKey.arrowDown), (dr: 1, dc: 0));
    expect(move(LogicalKeyboardKey.arrowLeft), (dr: 0, dc: -1));
    expect(move(LogicalKeyboardKey.pageUp), (dr: -10, dc: 0));
    expect(move(LogicalKeyboardKey.end), (dr: 0, dc: 6));
    expect(move(LogicalKeyboardKey.keyA), isNull);
  });
}
