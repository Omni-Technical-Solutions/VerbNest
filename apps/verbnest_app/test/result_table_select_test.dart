import 'dart:convert';

import 'package:flutter/gestures.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:verbnest_app/src/widgets/result_table_view.dart';
import 'package:verbnest_core/verbnest_core.dart';

import 'result_table_view_test.dart' as base show app, pump;
import 'result_table_view_test.dart' show pets;

ResultTable sample() => tableFromJson([
  {
    'id': 1,
    'name': 'Rex',
    'age': 4,
    'note': 'a, "b"',
    'tags': ['x', 'y'],
  },
  {'id': 2, 'name': 'Tom', 'age': 2.5, 'note': null, 'tags': []},
  {
    'id': 3,
    'name': 'Ann',
    'age': 10,
    'note': 'line\nbreak',
    'tags': ['z'],
  },
])!;

Finder cell(int r, int c) => find.byKey(ValueKey('table-cell-$r-$c'));

class Clip {
  String? text;
  void install(WidgetTester t) {
    t.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      SystemChannels.platform,
      (call) async {
        if (call.method == 'Clipboard.setData') {
          text = (call.arguments as Map)['text'] as String?;
        }
        return null;
      },
    );
    addTearDown(
      () => t.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform,
        null,
      ),
    );
  }
}

final _mice = Expando<TestGesture>();

/// One mouse per test: the framework rejects a second pointer for the same
/// device.
Future<TestGesture> mouse(WidgetTester t) async {
  var g = _mice[t];
  if (g == null) {
    g = await t.createGesture(kind: PointerDeviceKind.mouse);
    await g.addPointer(location: const Offset(5, 5));
    addTearDown(g.removePointer);
    _mice[t] = g;
  }
  return g;
}

Future<void> click(WidgetTester t, Finder f) async {
  final g = await mouse(t);
  await g.down(t.getCenter(f));
  await g.up();
  await t.pump();
}

Future<void> chord(
  WidgetTester t,
  LogicalKeyboardKey mod,
  LogicalKeyboardKey key,
) async {
  await t.sendKeyDownEvent(mod);
  await t.sendKeyEvent(key);
  await t.sendKeyUpEvent(mod);
  await t.pump();
}

Future<void> openMenu(WidgetTester t) async {
  // The "Copied" toast sits over the footer for a few seconds; its timer
  // starts when it has slid in, so it takes two steps to clear.
  await t.pump(const Duration(seconds: 5));
  await t.pump(const Duration(seconds: 5));
  await t.pump(const Duration(seconds: 1));
  await t.tap(find.byKey(const Key('table-actions')));
  await t.pumpAndSettle();
}

const _big = Size(800, 1000);

/// A window tall enough for the whole menu.
Future<void> pump(WidgetTester t, ResultTable table, {String filter = ''}) =>
    base.pump(
      t,
      base.app(table, filter: filter, size: _big),
      size: _big,
    );

void main() {
  testWidgets('a click selects a cell; Cmd+C copies it', (t) async {
    final clip = Clip()..install(t);
    await pump(t, sample());
    await click(t, cell(1, 1));
    await chord(t, LogicalKeyboardKey.metaLeft, LogicalKeyboardKey.keyC);
    expect(clip.text, 'Tom');
    await t.pump(const Duration(seconds: 3));
  });

  testWidgets('Shift-click extends to a range, copied as tab-separated', (
    t,
  ) async {
    final clip = Clip()..install(t);
    await pump(t, sample());
    await click(t, cell(0, 0));
    await t.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
    await click(t, cell(1, 2));
    await t.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
    expect(find.textContaining('6 cells selected'), findsOneWidget);
    await chord(t, LogicalKeyboardKey.controlLeft, LogicalKeyboardKey.keyC);
    expect(clip.text, '1\tRex\t4\n2\tTom\t2.5');
    await t.pump(const Duration(seconds: 3));
  });

  testWidgets('dragging with a mouse selects a range', (t) async {
    await pump(t, sample());
    final g = await mouse(t);
    await g.down(t.getCenter(cell(0, 1)));
    await g.moveTo(t.getCenter(cell(2, 2)));
    await g.up();
    await t.pump();
    expect(find.textContaining('6 cells selected'), findsOneWidget);
  });

  testWidgets('a row number selects the row; the corner selects all', (
    t,
  ) async {
    final clip = Clip()..install(t);
    await pump(t, sample());
    final number = find.descendant(
      of: find.byKey(const ValueKey('table-row-1')),
      matching: find.text('2'),
    );
    // The row number "2" is the one in the pinned column (the id cell is "2" too).
    await click(t, number.last);
    expect(find.textContaining('5 cells selected'), findsOneWidget);
    await t.tap(find.byKey(const Key('table-select-all')));
    await t.pump();
    expect(find.textContaining('15 cells selected'), findsOneWidget);
    await chord(t, LogicalKeyboardKey.metaLeft, LogicalKeyboardKey.keyC);
    // A line break inside a cell becomes a space, so one line per row.
    expect(clip.text!.split('\n').length, 3);
    await t.pump(const Duration(seconds: 3));
  });

  testWidgets('arrow keys move the focus; Shift extends; Escape clears', (
    t,
  ) async {
    await pump(t, sample());
    await click(t, cell(0, 0));
    await t.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    await t.sendKeyEvent(LogicalKeyboardKey.arrowRight);
    await t.pump();
    // Focus is on row 1, column 1: copy it.
    final clip = Clip()..install(t);
    await chord(t, LogicalKeyboardKey.metaLeft, LogicalKeyboardKey.keyC);
    expect(clip.text, 'Tom');
    await t.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
    await t.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    await t.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
    await t.pump();
    expect(find.textContaining('2 cells selected'), findsOneWidget);
    await t.sendKeyEvent(LogicalKeyboardKey.escape);
    await t.pump();
    expect(find.textContaining('cells selected'), findsNothing);
    await t.pump(const Duration(seconds: 3));
  });

  testWidgets('Cmd+A selects everything', (t) async {
    await pump(t, sample());
    await click(t, cell(0, 0));
    await chord(t, LogicalKeyboardKey.metaLeft, LogicalKeyboardKey.keyA);
    expect(find.textContaining('15 cells selected'), findsOneWidget);
  });

  testWidgets('the menu copies as CSV, JSON and Markdown', (t) async {
    final clip = Clip()..install(t);
    await pump(t, sample());
    await click(t, cell(0, 0));
    await t.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
    await click(t, cell(2, 1));
    await t.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);

    await openMenu(t);
    await t.tap(find.byKey(const Key('menu-copy-csv')));
    await t.pumpAndSettle(const Duration(seconds: 3));
    expect(clip.text, 'id,name\r\n1,Rex\r\n2,Tom\r\n3,Ann\r\n');

    await openMenu(t);
    await t.tap(find.byKey(const Key('menu-copy-json')));
    await t.pumpAndSettle(const Duration(seconds: 3));
    expect(jsonDecode(clip.text!), [
      {'id': 1, 'name': 'Rex'},
      {'id': 2, 'name': 'Tom'},
      {'id': 3, 'name': 'Ann'},
    ]);

    await openMenu(t);
    await t.tap(find.byKey(const Key('menu-copy-markdown')));
    await t.pumpAndSettle(const Duration(seconds: 3));
    expect(clip.text, startsWith('| id | name |\n| --- | --- |\n| 1 | Rex |'));

    await openMenu(t);
    await t.tap(find.byKey(const Key('menu-copy-headers')));
    await t.pumpAndSettle(const Duration(seconds: 3));
    expect(clip.text, startsWith('id\tname\n1\tRex'));
  });

  testWidgets('with no selection the menu copies every row shown', (t) async {
    final clip = Clip()..install(t);
    await pump(t, sample(), filter: 'a');
    await openMenu(t);
    expect(
      t
          .widget<PopupMenuItem<String>>(
            find.byKey(const Key('menu-copy-cells')),
          )
          .enabled,
      isFalse,
    );
    await t.tap(find.byKey(const Key('menu-copy-csv')));
    await t.pumpAndSettle(const Duration(seconds: 3));
    // "Rex" has no "a"; the filter "a" keeps Ann and the "a, ..." note row.
    final lines = clip.text!.trim().split('\r\n');
    expect(lines.first, startsWith('id,name'));
    expect(lines.length, 3);
  });

  testWidgets('Save as CSV hands every row shown to the host', (t) async {
    String? saved;
    await base.pump(
      t,
      MaterialApp(
        home: Scaffold(
          body: ResultTableView(
            table: sample(),
            onSaveCsv: (csv) async => saved = csv,
          ),
        ),
      ),
      size: _big,
    );
    await openMenu(t);
    await t.tap(find.byKey(const Key('menu-save-csv')));
    await t.pumpAndSettle();
    expect(saved, startsWith('id,name,age,note,tags\r\n1,Rex,4,"a, ""b""",'));
    expect(parseCsvRows(saved!).length, 4);
    // Without a host the item is absent.
    await pump(t, sample());
    await openMenu(t);
    expect(find.byKey(const Key('menu-save-csv')), findsNothing);
  });

  testWidgets('a double click, and Enter, show the full value', (t) async {
    await pump(t, sample());
    final g = await mouse(t);
    final at = t.getCenter(cell(2, 3));
    await g.down(at);
    await g.up();
    await t.pump(const Duration(milliseconds: 40));
    await g.down(at);
    await g.up();
    await t.pumpAndSettle();
    expect(find.byKey(const Key('table-value')), findsOneWidget);
    expect(
      t.widget<SelectableText>(find.byKey(const Key('table-value'))).data,
      'line\nbreak',
    );
    await t.tap(find.text('Close'));
    await t.pumpAndSettle();
    // Enter on the focused cell does the same; nested values show as JSON.
    await click(t, cell(0, 4));
    await t.sendKeyEvent(LogicalKeyboardKey.enter);
    await t.pumpAndSettle();
    expect(
      t.widget<SelectableText>(find.byKey(const Key('table-value'))).data,
      '[\n  "x",\n  "y"\n]',
    );
    final clip = Clip()..install(t);
    await t.tap(find.byKey(const Key('table-value-copy')));
    await t.pump();
    expect(clip.text, '[\n  "x",\n  "y"\n]');
    await t.pump(const Duration(seconds: 3));
  });

  testWidgets('on a touch screen a tap shows the value', (t) async {
    await pump(t, sample());
    await t.tap(cell(1, 1));
    await t.pumpAndSettle();
    expect(find.byKey(const Key('table-value')), findsOneWidget);
    expect(find.text('Tom'), findsWidgets);
  });

  testWidgets('a null value shows as null in the detail view', (t) async {
    await pump(t, sample());
    await t.tap(cell(1, 3));
    await t.pumpAndSettle();
    expect(
      t.widget<SelectableText>(find.byKey(const Key('table-value'))).data,
      'null',
    );
  });

  testWidgets('a header right click offers select column, fit and clear sort', (
    t,
  ) async {
    await pump(t, sample());
    // Sort the age column so "Clear sort" shows.
    await t.tap(find.byKey(const ValueKey('table-sort-2')));
    await t.pump();
    final g = await t.createGesture(
      kind: PointerDeviceKind.mouse,
      buttons: kSecondaryMouseButton,
    );
    await g.addPointer(location: const Offset(5, 5));
    addTearDown(g.removePointer);
    await g.down(t.getCenter(find.byKey(const ValueKey('table-sort-2'))));
    await g.up();
    await t.pumpAndSettle();
    expect(find.byKey(const Key('menu-clear-sort')), findsOneWidget);
    await t.tap(find.byKey(const Key('menu-select-column')));
    await t.pumpAndSettle();
    expect(find.textContaining('3 cells selected'), findsOneWidget);
    // Clear the sort from the same menu.
    await g.down(t.getCenter(find.byKey(const ValueKey('table-sort-2'))));
    await g.up();
    await t.pumpAndSettle();
    await t.tap(find.byKey(const Key('menu-clear-sort')));
    await t.pumpAndSettle();
    expect(find.byKey(const Key('table-sort-asc-2')), findsNothing);
  });

  testWidgets('changing the filter or the sort clears the selection', (
    t,
  ) async {
    await pump(t, sample());
    await click(t, cell(0, 0));
    await t.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
    await click(t, cell(1, 1));
    await t.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
    expect(find.textContaining('4 cells selected'), findsOneWidget);
    await t.tap(find.byKey(const ValueKey('table-sort-1')));
    await t.pump();
    expect(find.textContaining('cells selected'), findsNothing);
  });

  testWidgets('the selected cells and the row number are highlighted', (
    t,
  ) async {
    await pump(t, pets());
    await click(t, cell(0, 1));
    final box = t.widget<Container>(cell(0, 1));
    expect((box.decoration as BoxDecoration).color, isNotNull);
    expect(box.foregroundDecoration, isNotNull);
    final other = t.widget<Container>(cell(1, 1));
    expect((other.decoration as BoxDecoration).color, isNull);
  });
}

Future<void> pumpForComplete(WidgetTester t, ResultTable table) =>
    pump(t, table);
