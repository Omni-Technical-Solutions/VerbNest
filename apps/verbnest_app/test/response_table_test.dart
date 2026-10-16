import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:verbnest_app/src/state/editor_state.dart';
import 'package:verbnest_app/src/widgets/code_view.dart';
import 'package:verbnest_app/src/widgets/response_view.dart';
import 'package:verbnest_app/src/widgets/result_table_view.dart';
import 'package:verbnest_core/verbnest_core.dart';

import 'step7_test.dart' show record;

Future<void> show(
  WidgetTester t,
  String body,
  String contentType, {
  Size size = const Size(900, 700),
}) async {
  t.view.physicalSize = size;
  t.view.devicePixelRatio = 1;
  addTearDown(t.view.reset);
  await t.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: ResponseView(
          state: EditorState(
            item: const HttpRequestItem(id: 'x', name: 'x'),
            response: record(body, [('Content-Type', contentType)]),
          ),
        ),
      ),
    ),
  );
  await t.pump();
}

Future<void> openTable(WidgetTester t) async {
  // On a phone the table is an item in the body menu, not a segment.
  final more = find.byKey(const Key('body-more'));
  if (more.evaluate().isNotEmpty) {
    await t.tap(more);
    await t.pumpAndSettle();
    await t.tap(find.byKey(const Key('menu-table')));
    await t.pumpAndSettle();
    return;
  }
  await t.tap(
    find.descendant(
      of: find.byKey(const Key('body-view')),
      matching: find.text('Table'),
    ),
  );
  await t.pump();
}

const pets =
    '[{"id":1,"name":"Rex","tags":["a"]},{"id":2,"name":"Tom","tags":[]},'
    '{"id":3,"name":"Ann","tags":["b","c"]}]';

void main() {
  testWidgets('a list of records offers a Table segment; Pretty stays first', (
    t,
  ) async {
    await show(t, pets, 'application/json');
    expect(find.byType(CodeView), findsOneWidget);
    expect(find.byType(ResultTableView), findsNothing);
    await openTable(t);
    expect(find.byType(ResultTableView), findsOneWidget);
    expect(find.byType(CodeView), findsNothing);
    expect(find.text('3 rows, 3 columns'), findsOneWidget);
    // Back to Pretty.
    await t.tap(
      find.descendant(
        of: find.byKey(const Key('body-view')),
        matching: find.text('Pretty'),
      ),
    );
    await t.pump();
    expect(find.byType(CodeView), findsOneWidget);
  });

  testWidgets('the Table segment is absent for bodies that are not tabular', (
    t,
  ) async {
    for (final (body, type) in [
      ('plain text', 'text/plain'),
      ('{bad json', 'application/json'),
      ('"just a string"', 'application/json'),
      ('<html></html>', 'text/html'),
    ]) {
      await show(t, body, type);
      expect(
        find.descendant(
          of: find.byKey(const Key('body-view')),
          matching: find.text('Table'),
        ),
        findsNothing,
        reason: type + body,
      );
    }
  });

  testWidgets('the search box filters the rows', (t) async {
    await show(t, pets, 'application/json');
    await openTable(t);
    await t.enterText(find.byKey(const Key('response-search')), 'ann');
    await t.pump();
    expect(find.textContaining('1 of 3 rows'), findsOneWidget);
    expect(find.text('Rex'), findsNothing);
    await t.enterText(find.byKey(const Key('response-search')), '');
    await t.pump();
    expect(find.text('3 rows, 3 columns'), findsOneWidget);
  });

  testWidgets('the JSONPath filter feeds the table', (t) async {
    await show(
      t,
      '{"items":[{"id":1,"k":"a"},{"id":2,"k":"b"},{"id":3,"k":"a"}]}',
      'application/json',
    );
    await openTable(t);
    expect(find.text('3 rows, 2 columns'), findsOneWidget);
    await t.enterText(find.byKey(const Key('response-filter')), r'$.items[0]');
    await t.pump();
    // One object: a Key / Value table.
    expect(find.textContaining('Key'), findsWidgets);
    expect(find.text('2 rows, 2 columns'), findsOneWidget);
    await t.enterText(
      find.byKey(const Key('response-filter')),
      r'$.items[0:2]',
    );
    await t.pump();
  });

  testWidgets('several arrays: a Rows from menu picks the one to use', (
    t,
  ) async {
    await show(
      t,
      '{"items":[{"a":1},{"a":2},{"a":3}],"links":[{"rel":"self"}]}',
      'application/json',
    );
    await openTable(t);
    expect(find.text('3 rows, 1 column'), findsOneWidget);
    await t.tap(find.byKey(const Key('table-source')));
    await t.pumpAndSettle();
    await t.tap(find.text(r'$.links (1)').last);
    await t.pumpAndSettle();
    expect(find.text('1 row, 1 column'), findsOneWidget);
    expect(find.text('self'), findsOneWidget);
  });

  testWidgets('nested values flatten into dotted columns on request', (
    t,
  ) async {
    await show(
      t,
      '[{"id":1,"address":{"city":"Perth"}},{"id":2,"address":{"city":"Hobart"}}]',
      'application/json',
    );
    await openTable(t);
    expect(find.text('address'), findsOneWidget);
    await t.tap(find.byKey(const Key('table-flatten')));
    await t.pump();
    expect(find.text('address.city'), findsOneWidget);
    expect(find.text('Perth'), findsOneWidget);
  });

  testWidgets('an array of arrays can use its first row as the header', (
    t,
  ) async {
    await show(t, '[["id","name"],[1,"Rex"],[2,"Tom"]]', 'application/json');
    await openTable(t);
    expect(find.text('1'), findsWidgets);
    await t.tap(find.byKey(const Key('table-header-row')));
    await t.pump();
    expect(find.text('name'), findsOneWidget);
    expect(find.text('2 rows, 2 columns'), findsOneWidget);
  });

  testWidgets('CSV and XML bodies get a table too', (t) async {
    await show(t, 'id,name\r\n1,Rex\r\n2,Tom\r\n', 'text/csv');
    await openTable(t);
    expect(find.text('2 rows, 2 columns'), findsOneWidget);
    await show(
      t,
      '<pets><pet id="1"><name>Rex</name></pet><pet id="2"><name>Tom</name></pet></pets>',
      'application/xml',
    );
    await openTable(t);
    expect(find.text('@id'), findsOneWidget);
  });

  testWidgets('Hex and Raw leave the table; the Wrap button hides in it', (
    t,
  ) async {
    await show(t, pets, 'application/json');
    expect(find.byKey(const Key('wrap-body')), findsOneWidget);
    await openTable(t);
    expect(find.byKey(const Key('wrap-body')), findsNothing);
    await t.tap(
      find.descendant(
        of: find.byKey(const Key('body-view')),
        matching: find.text('Hex'),
      ),
    );
    await t.pump();
    expect(find.byType(ResultTableView), findsNothing);
    await t.tap(
      find.descendant(
        of: find.byKey(const Key('body-view')),
        matching: find.text('Table'),
      ),
    );
    await t.pump();
    expect(find.byType(ResultTableView), findsOneWidget);
  });

  testWidgets('copying the body still copies the text, not the grid', (
    t,
  ) async {
    String? copied;
    t.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      SystemChannels.platform,
      (call) async {
        if (call.method == 'Clipboard.setData') {
          copied = (call.arguments as Map)['text'] as String?;
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
    await show(t, pets, 'application/json');
    await openTable(t);
    await t.tap(find.byKey(const Key('copy-body')));
    await t.pump();
    expect(copied, contains('"name": "Rex"'));
  });

  for (final w in [280.0, 320.0, 360.0, 402.0]) {
    testWidgets('the table opens on a ${w.toInt()} pt phone', (t) async {
      await show(t, pets, 'application/json', size: Size(w, 700));
      await openTable(t);
      expect(t.takeException(), isNull);
      expect(find.byType(ResultTableView), findsOneWidget);
    });
  }

  testWidgets('on a phone the menu switches the table on and off and copies', (
    t,
  ) async {
    String? copied;
    t.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      SystemChannels.platform,
      (call) async {
        if (call.method == 'Clipboard.setData') {
          copied = (call.arguments as Map)['text'] as String?;
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
    await show(t, pets, 'application/json', size: const Size(402, 700));
    // Three segments only; the table is in the menu.
    expect(
      find.descendant(
        of: find.byKey(const Key('body-view')),
        matching: find.text('Table'),
      ),
      findsNothing,
    );
    await openTable(t);
    expect(find.byType(ResultTableView), findsOneWidget);
    await t.tap(find.byKey(const Key('body-more')));
    await t.pumpAndSettle();
    // Wrap does not apply to the grid; table is ticked.
    expect(find.byKey(const Key('menu-wrap')), findsNothing);
    await t.tap(find.byKey(const Key('menu-table')));
    await t.pumpAndSettle();
    expect(find.byType(ResultTableView), findsNothing);
    expect(find.byType(CodeView), findsOneWidget);
    await t.tap(find.byKey(const Key('body-more')));
    await t.pumpAndSettle();
    await t.tap(find.byKey(const Key('menu-copy')));
    await t.pumpAndSettle();
    expect(copied, contains('"name": "Rex"'));
    expect(t.takeException(), isNull);
  });
}
