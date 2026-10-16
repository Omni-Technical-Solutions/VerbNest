import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:verbnest_app/src/widgets/result_table_view.dart';
import 'package:verbnest_core/verbnest_core.dart';

import 'response_table_test.dart' show openTable, show;
import 'result_table_select_test.dart'
    show Clip, chord, click, openMenu, pumpForComplete;
import 'result_table_view_test.dart' as base show pump;

import 'package:flutter/gestures.dart';

/// Everything in the body reaches the table: what the grid draws is capped
/// (10,000 rows, 200 columns) but search, copy and export have all of it, and
/// the whole body (fields beside the rows, XML siblings) can be chosen.
void main() {
  testWidgets('select all copies every row, past the 10,000 drawn', (t) async {
    final clip = Clip()..install(t);
    final big = tableFromJson([
      for (var i = 0; i < 12000; i++) {'id': i, 'name': 'row $i'},
    ])!;
    await pumpForComplete(t, big);
    expect(find.textContaining('Showing the first 10000 rows'), findsOneWidget);
    await t.tap(find.byKey(const Key('table-select-all')));
    await t.pump();
    // The footer counts what a copy will take.
    expect(find.textContaining('24000 cells selected'), findsOneWidget);
    await chord(t, LogicalKeyboardKey.metaLeft, LogicalKeyboardKey.keyC);
    final lines = clip.text!.split('\n');
    expect(lines.length, 12000);
    expect(lines.last, '11999\trow 11999');
    await t.pump(const Duration(seconds: 3));
  });

  testWidgets('a whole column copies every row too', (t) async {
    final clip = Clip()..install(t);
    final big = tableFromJson([
      for (var i = 0; i < 12000; i++) {'id': i, 'name': 'row $i'},
    ])!;
    await pumpForComplete(t, big);
    // Header menu: Select column on "name".
    final g = await t.createGesture(
      kind: PointerDeviceKind.mouse,
      buttons: kSecondaryMouseButton,
    );
    await g.addPointer(location: const Offset(5, 5));
    addTearDown(g.removePointer);
    await g.down(t.getCenter(find.byKey(const ValueKey('table-sort-1'))));
    await g.up();
    await t.pumpAndSettle();
    await t.tap(find.byKey(const Key('menu-select-column')));
    await t.pumpAndSettle();
    expect(find.textContaining('12000 cells selected'), findsOneWidget);
    await chord(t, LogicalKeyboardKey.metaLeft, LogicalKeyboardKey.keyC);
    expect(clip.text!.split('\n').length, 12000);
    expect(clip.text!.split('\n').last, 'row 11999');
    await t.pump(const Duration(seconds: 3));
  });

  testWidgets('230 columns: 200 are drawn, all 230 copy and export', (t) async {
    final clip = Clip()..install(t);
    String? csv;
    final wide = tableFromJson([
      {for (var i = 0; i < 230; i++) 'c$i': i},
      {for (var i = 0; i < 230; i++) 'c$i': i + 1000},
    ])!;
    await base.pump(
      t,
      MaterialApp(
        home: Scaffold(
          body: ResultTableView(table: wide, onSaveCsv: (c) async => csv = c),
        ),
      ),
      size: const Size(800, 1000),
    );
    expect(find.textContaining('30 more columns not shown'), findsOneWidget);
    expect(find.byKey(const ValueKey('table-header-199')), findsOneWidget);
    expect(find.byKey(const ValueKey('table-header-200')), findsNothing);
    // A row copied from its number has all 230 values.
    final number = find.descendant(
      of: find.byKey(const ValueKey('table-row-1')),
      matching: find.text('2'),
    );
    await click(t, number.last);
    await chord(t, LogicalKeyboardKey.metaLeft, LogicalKeyboardKey.keyC);
    final fields = clip.text!.split('\t');
    expect(fields.length, 230);
    expect(fields.first, '1000');
    expect(fields.last, '1229');
    await t.pump(const Duration(seconds: 6));
    await t.pump(const Duration(seconds: 6));
    // Save as CSV has every column.
    await openMenu(t);
    await t.tap(find.byKey(const Key('menu-save-csv')));
    await t.pumpAndSettle();
    final rows = parseCsvRows(csv!);
    expect(rows.length, 3);
    expect(rows.first.length, 230);
    expect(rows.first.last, 'c229');
    expect(rows.last.last, '1229');
  });

  testWidgets('the whole body shows the fields beside the rows', (t) async {
    await show(
      t,
      '{"page":3,"total":42,"items":[{"id":1},{"id":2}],"links":[{"rel":"self"}]}',
      'application/json',
    );
    await openTable(t);
    // The rows are the largest list; the other fields are one choice away.
    expect(find.text('2 rows, 1 column'), findsOneWidget);
    await t.tap(find.byKey(const Key('table-source')));
    await t.pumpAndSettle();
    expect(find.text('Whole body (4)'), findsOneWidget);
    await t.tap(find.text('Whole body (4)').last);
    await t.pumpAndSettle();
    expect(find.text('page'), findsOneWidget);
    expect(find.text('3'), findsWidgets);
    expect(find.text('total'), findsOneWidget);
    expect(find.text('42'), findsOneWidget);
    expect(find.text('4 rows, 2 columns'), findsOneWidget);
  });

  testWidgets('XML: the whole document includes what is beside the rows', (
    t,
  ) async {
    await show(
      t,
      '<r v="1"><meta>m</meta><item id="1">t<sub>s</sub></item><item id="2"/></r>',
      'application/xml',
    );
    await openTable(t);
    expect(find.text('@id'), findsOneWidget);
    expect(find.text('#text'), findsOneWidget);
    await t.tap(find.byKey(const Key('table-source')));
    await t.pumpAndSettle();
    await t.tap(find.textContaining('Whole body').last);
    await t.pumpAndSettle();
    expect(find.text('@v'), findsOneWidget);
    expect(find.text('meta'), findsOneWidget);
    expect(find.text('m'), findsOneWidget);
  });

  testWidgets('a float keeps its decimal point in the grid and the copy', (
    t,
  ) async {
    final clip = Clip()..install(t);
    await show(
      t,
      '[{"price":10.0,"qty":3},{"price":2.50,"qty":4}]',
      'application/json',
    );
    await openTable(t);
    expect(find.text('10.0'), findsOneWidget);
    expect(find.text('2.5'), findsOneWidget);
    await t.tap(find.byKey(const Key('table-select-all')));
    await t.pump();
    await chord(t, LogicalKeyboardKey.metaLeft, LogicalKeyboardKey.keyC);
    expect(clip.text, '10.0\t3\n2.5\t4');
    await t.pump(const Duration(seconds: 3));
  });
}
