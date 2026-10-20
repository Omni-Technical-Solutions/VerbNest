import 'package:flutter_test/flutter_test.dart';
import 'package:verbnest_app/src/widgets/result_table_selection.dart';

/// The selection rules of the results table, without any widgets.
void main() {
  const shown = 10, cols = 4;

  test('nothing is selected at first', () {
    final s = TableSelection();
    expect(s.hasSelection, isFalse);
    expect(s.range(shown: shown, cols: cols), isNull);
    expect(s.isSelected(0, 0, shown: shown, cols: cols), isFalse);
  });

  test('a cell, then a block by extending', () {
    final s = TableSelection()..selectCell(2, 1);
    expect(s.range(shown: shown, cols: cols), (r0: 2, r1: 2, c0: 1, c1: 1));
    expect(s.isFocus(2, 1), isTrue);
    s.selectCell(4, 3, extend: true);
    expect(s.range(shown: shown, cols: cols), (r0: 2, r1: 4, c0: 1, c1: 3));
    expect(s.isSelected(3, 2, shown: shown, cols: cols), isTrue);
    expect(s.isSelected(5, 2, shown: shown, cols: cols), isFalse);
    // Extending backwards keeps the anchor.
    s.selectCell(0, 0, extend: true);
    expect(s.range(shown: shown, cols: cols), (r0: 0, r1: 2, c0: 0, c1: 1));
  });

  test('a click without extending starts again', () {
    final s = TableSelection()
      ..selectCell(1, 1)
      ..selectCell(3, 3, extend: true)
      ..selectCell(7, 0);
    expect(s.range(shown: shown, cols: cols), (r0: 7, r1: 7, c0: 0, c1: 0));
  });

  test('a row covers every column, and extends over rows', () {
    final s = TableSelection()..selectRow(3);
    expect(s.range(shown: shown, cols: cols), (r0: 3, r1: 3, c0: 0, c1: 3));
    expect(s.isFocus(3, 0), isFalse, reason: 'a whole row has no focus cell');
    s.selectRow(5, extend: true);
    expect(s.range(shown: shown, cols: cols), (r0: 3, r1: 5, c0: 0, c1: 3));
  });

  test('a column covers every row', () {
    final s = TableSelection()..selectColumn(2);
    expect(s.range(shown: shown, cols: cols), (r0: 0, r1: 9, c0: 2, c1: 2));
  });

  test('select all covers everything drawn', () {
    final s = TableSelection()..selectAll();
    expect(s.range(shown: shown, cols: cols), (r0: 0, r1: 9, c0: 0, c1: 3));
  });

  test('the range stays inside what is drawn', () {
    final s = TableSelection()..selectCell(8, 3);
    expect(s.range(shown: 5, cols: 2), (r0: 4, r1: 4, c0: 1, c1: 1));
    expect(s.range(shown: 0, cols: 2), isNull);
  });

  test('a whole row or column counts the rows and columns not drawn too', () {
    int count(TableSelection s) => s.selectedCount(
      shown: shown,
      cols: cols,
      totalRows: 500,
      totalCols: 230,
    );
    expect(count(TableSelection()), 0);
    expect(count(TableSelection()..selectCell(1, 1)), 1);
    expect(count(TableSelection()..selectRow(2)), 230);
    expect(count(TableSelection()..selectColumn(1)), 500);
    expect(count(TableSelection()..selectAll()), 500 * 230);
    final block = TableSelection()
      ..selectCell(1, 0)
      ..selectCell(3, 2, extend: true);
    expect(count(block), 3 * 3);
  });

  test('clear forgets everything', () {
    final s = TableSelection()
      ..selectAll()
      ..clear();
    expect(s.hasSelection, isFalse);
    expect(s.wholeRows, isFalse);
    expect(s.wholeCols, isFalse);
  });
}
