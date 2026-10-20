import 'package:flutter/painting.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:verbnest_app/src/widgets/result_table_sizing.dart';
import 'package:verbnest_core/verbnest_core.dart';

/// Where the results table starts its column widths.
ResultTable table(List<List<Object?>> rows) => ResultTable(const [
  TableColumn('id', ColumnType.number),
  TableColumn('name', ColumnType.text),
], rows);

double fit(ResultTable t, int col) => TableColumnSizer.fit(
  table: t,
  col: col,
  drawn: 2,
  style: const TextStyle(fontSize: 13),
  scaler: TextScaler.noScaling,
  typeName: (type) => type.name,
);

void main() {
  test('a width is a whole number of pixels inside the fit range', () {
    final t = table([
      [1, 'Tom'],
      [2, 'Ziggy, the great'],
    ]);
    for (var c = 0; c < 2; c++) {
      final w = fit(t, c);
      expect(w, w.roundToDouble());
      expect(
        w,
        inInclusiveRange(TableColumnSizer.fitMin, TableColumnSizer.fitMax),
      );
    }
  });

  test('longer text gets a wider column, up to the limit', () {
    final short = fit(
      table([
        [1, 'a'],
      ]),
      1,
    );
    final long = fit(
      table([
        [1, 'a much longer value in this cell'],
      ]),
      1,
    );
    final huge = fit(
      table([
        [1, 'x' * 500],
      ]),
      1,
    );
    expect(long, greaterThan(short));
    expect(huge, TableColumnSizer.fitMax);
  });

  test('shown text is cut at the cell limit and null is empty', () {
    expect(TableColumnSizer.shownText(null), '');
    expect(
      TableColumnSizer.shownText('y' * (ResultTable.maxCellChars + 50)).length,
      ResultTable.maxCellChars,
    );
  });
}
