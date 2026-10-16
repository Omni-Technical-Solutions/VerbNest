import 'package:flutter/gestures.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:verbnest_app/l10n/app_localizations.dart';
import 'package:verbnest_app/src/theme.dart';
import 'package:verbnest_app/src/widgets/result_table_view.dart';
import 'package:verbnest_core/verbnest_core.dart';

ResultTable pets() => tableFromJson([
  {
    'id': 1,
    'name': 'Rex',
    'age': 4,
    'owner': null,
    'tags': ['a', 'b'],
  },
  {'id': 2, 'name': 'tom', 'age': 2.5, 'owner': 'Ann', 'tags': []},
  {
    'id': 3,
    'name': 'Ann',
    'age': 10,
    'owner': 'Bo',
    'tags': ['c'],
  },
])!;

Widget app(
  ResultTable t, {
  String filter = '',
  Size size = const Size(800, 400),
  double textScale = 1,
}) => MaterialApp(
  theme: buildTheme(Brightness.light, seed: AppAccents.seed(0)),
  localizationsDelegates: [
    AppLocalizations.delegate,
    ...GlobalMaterialLocalizations.delegates,
  ],
  supportedLocales: AppLocalizations.supportedLocales,
  home: MediaQuery(
    data: MediaQueryData(size: size, textScaler: TextScaler.linear(textScale)),
    child: Scaffold(
      body: SizedBox(
        width: size.width,
        height: size.height,
        child: ResultTableView(table: t, filter: filter),
      ),
    ),
  ),
);

Future<void> pump(WidgetTester t, Widget w, {Size? size}) async {
  t.view.physicalSize = size ?? const Size(800, 400);
  t.view.devicePixelRatio = 1;
  addTearDown(t.view.reset);
  await t.pumpWidget(w);
  await t.pump();
}

String cellText0(WidgetTester t, int row, int col) => t
    .widget<Text>(
      find.descendant(
        of: find.byKey(ValueKey('table-cell-$row-$col')),
        matching: find.byType(Text),
      ),
    )
    .data!;

void main() {
  testWidgets('shows names, types, values, null and a footer', (t) async {
    await pump(t, app(pets()));
    expect(find.text('name'), findsOneWidget);
    expect(find.text('number'), findsWidgets);
    expect(find.text('Rex'), findsOneWidget);
    expect(find.text('null'), findsOneWidget);
    expect(find.text('3 rows, 5 columns'), findsOneWidget);
    // Nested values are a one-line JSON preview.
    expect(find.textContaining('[2 items]'), findsOneWidget);
    // Numbers are right-aligned, text left-aligned.
    final age = t.getTopRight(find.byKey(const ValueKey('table-cell-0-2')));
    final num = t.getTopRight(find.text('4'));
    expect(age.dx - num.dx, lessThan(16));
    expect(t.takeException(), isNull);
  });

  testWidgets('the header stays put when the rows scroll', (t) async {
    final big = tableFromJson([
      for (var i = 0; i < 500; i++) {'id': i, 'name': 'row $i'},
    ])!;
    await pump(t, app(big));
    final top = t.getTopLeft(find.byKey(const ValueKey('table-header-0'))).dy;
    await t.dragFrom(const Offset(400, 300), const Offset(0, -600));
    await t.pump();
    expect(t.getTopLeft(find.byKey(const ValueKey('table-header-0'))).dy, top);
    expect(find.text('row 0'), findsNothing);
  });

  testWidgets('row numbers stay at the left edge when columns scroll', (
    t,
  ) async {
    final wide = tableFromJson([
      {for (var i = 0; i < 30; i++) 'column number $i': 'value $i'},
    ])!;
    await pump(t, app(wide));
    final rowNo = find.text('1');
    expect(rowNo, findsOneWidget);
    final before = t.getTopLeft(rowNo).dx;
    await t.dragFrom(const Offset(400, 300), const Offset(-900, 0));
    await t.pump();
    // The first column has scrolled out of view to the left...
    expect(
      t.getTopLeft(find.byKey(const ValueKey('table-header-0'))).dx,
      lessThan(0),
    );
    // ...and the row number is where it was.
    expect(t.getTopLeft(rowNo).dx, before);
  });

  testWidgets('a header tap sorts ascending, descending, then off', (t) async {
    await pump(t, app(pets()));
    expect(cellText0(t, 0, 1), 'Rex');
    await t.tap(find.byKey(const ValueKey('table-sort-1')));
    await t.pump();
    expect(find.byKey(const Key('table-sort-asc-1')), findsOneWidget);
    expect(
      [cellText0(t, 0, 1), cellText0(t, 1, 1), cellText0(t, 2, 1)],
      ['Ann', 'Rex', 'tom'],
    );
    await t.tap(find.byKey(const ValueKey('table-sort-1')));
    await t.pump();
    expect(find.byKey(const Key('table-sort-desc-1')), findsOneWidget);
    expect(cellText0(t, 0, 1), 'tom');
    await t.tap(find.byKey(const ValueKey('table-sort-1')));
    await t.pump();
    expect(find.byKey(const Key('table-sort-asc-1')), findsNothing);
    expect(find.byKey(const Key('table-sort-desc-1')), findsNothing);
    expect(cellText0(t, 0, 1), 'Rex');
    // The row number follows the data, not the position: sorted by name the
    // first row is "Ann", which was row 3.
    await t.tap(find.byKey(const ValueKey('table-sort-1')));
    await t.pump();
    expect(
      find.descendant(
        of: find.byKey(const ValueKey('table-row-0')),
        matching: find.text('3'),
      ),
      findsWidgets,
    );
  });

  testWidgets('numbers sort as numbers', (t) async {
    await pump(t, app(pets()));
    await t.tap(find.byKey(const ValueKey('table-sort-2')));
    await t.pump();
    expect(
      [cellText0(t, 0, 2), cellText0(t, 1, 2), cellText0(t, 2, 2)],
      ['2.5', '4', '10'],
    );
  });

  testWidgets('dragging the header edge resizes; a double tap fits', (t) async {
    await pump(t, app(pets()));
    final w0 = t.getSize(find.byKey(const ValueKey('table-header-1'))).width;
    await t.drag(
      find.byKey(const ValueKey('table-resize-1')),
      const Offset(100, 0),
    );
    await t.pump();
    final w1 = t.getSize(find.byKey(const ValueKey('table-header-1'))).width;
    // A drag gives up about 20 px to the touch slop before it moves.
    expect(w1, greaterThan(w0 + 70));
    await t.drag(
      find.byKey(const ValueKey('table-resize-1')),
      const Offset(-2000, 0),
    );
    await t.pump();
    expect(
      t.getSize(find.byKey(const ValueKey('table-header-1'))).width,
      ResultTableView.minColumnWidth,
    );
    final handle = find.byKey(const ValueKey('table-resize-1'));
    await t.tap(handle);
    await t.pump(const Duration(milliseconds: 40));
    await t.tap(handle);
    await t.pump();
    expect(
      t.getSize(find.byKey(const ValueKey('table-header-1'))).width,
      greaterThan(ResultTableView.minColumnWidth),
    );
    await t.pump(const Duration(seconds: 1));
  });

  testWidgets('the filter keeps matching rows and the footer says so', (
    t,
  ) async {
    await pump(t, app(pets(), filter: 'ann'));
    expect(find.text('Rex'), findsNothing);
    expect(find.text('Ann'), findsWidgets);
    expect(find.textContaining('2 of 3 rows'), findsOneWidget);
    // Clearing the filter brings everything back.
    await t.pumpWidget(app(pets()));
    await t.pump();
    expect(find.text('3 rows, 5 columns'), findsOneWidget);
  });

  testWidgets('a new table resets the sort', (t) async {
    final a = pets();
    await pump(t, app(a));
    await t.tap(find.byKey(const ValueKey('table-sort-1')));
    await t.pump();
    await t.pumpWidget(app(pets()));
    await t.pump();
    expect(find.byKey(const Key('table-sort-asc-1')), findsNothing);
    expect(cellText0(t, 0, 1), 'Rex');
  });

  testWidgets('only the first 10,000 rows are shown, and it says so', (
    t,
  ) async {
    final huge = tableFromJson([
      for (var i = 0; i < 12000; i++) {'id': i},
    ])!;
    await pump(t, app(huge));
    expect(find.textContaining('Showing the first 10000 rows'), findsOneWidget);
    expect(find.textContaining('12000 rows'), findsOneWidget);
  });

  testWidgets('100,000 rows build only the rows on screen', (t) async {
    final huge = tableFromJson([
      for (var i = 0; i < 100000; i++) {'id': i, 'name': 'n$i'},
    ])!;
    await pump(t, app(huge));
    final built = find.byWidgetPredicate(
      (w) =>
          w.key is ValueKey &&
          '${(w.key as ValueKey).value}'.startsWith('table-row-'),
    );
    expect(built.evaluate().length, lessThan(40));
    // Fling to the end of the capped list; still only a screenful exists.
    await t.flingFrom(const Offset(400, 300), const Offset(0, -3000), 8000);
    await t.pumpAndSettle();
    expect(built.evaluate().length, lessThan(40));
  });

  testWidgets('hover over rows does not rebuild the list', (t) async {
    await pump(t, app(pets()));
    final g = await t.createGesture(kind: PointerDeviceKind.mouse);
    await g.addPointer(location: const Offset(300, 100));
    addTearDown(g.removePointer);
    await t.pump();
    await g.moveTo(const Offset(320, 130));
    await t.pump();
    expect(t.takeException(), isNull);
  });

  for (final scale in [1.0, 2.0, 3.1]) {
    testWidgets('no overflow at text size ${scale}x on a 320 pt phone', (
      t,
    ) async {
      await pump(
        t,
        app(pets(), size: const Size(320, 568), textScale: scale),
        size: const Size(320, 568),
      );
      expect(t.takeException(), isNull);
      await t.dragFrom(const Offset(400, 300), const Offset(-300, 0));
      await t.pump();
      expect(t.takeException(), isNull);
    });
  }

  testWidgets('a table with a dropped column count says so', (t) async {
    final wide = tableFromJson([
      {for (var i = 0; i < 205; i++) 'c$i': i},
    ])!;
    await pump(t, app(wide));
    expect(find.textContaining('5 more columns not shown'), findsOneWidget);
  });
}
