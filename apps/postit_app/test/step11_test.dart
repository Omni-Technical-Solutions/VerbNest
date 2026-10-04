import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:postit_app/src/state/editor_state.dart';
import 'package:postit_app/src/state/var_text.dart';
import 'package:postit_app/src/widgets/kv_editor.dart';
import 'package:postit_app/src/widgets/synced_field.dart';
import 'package:postit_core/postit_core.dart';
import 'package:postit_http/postit_http.dart';

import 'step9_test.dart' show pumpEditor, setup;

void main() {
  group('var_text', () {
    test('finds tokens and the one under the caret', () {
      const t = 'a {{x}} b {{ y }}';
      expect(findTokens(t).map((e) => e.name), ['x', 'y']);
      expect(tokenAt(t, 4)!.name, 'x');
      expect(tokenAt(t, 8), isNull);
    });

    test('completion prefix and apply', () {
      expect(completionPrefix('http://{{ho', 11), 'ho');
      expect(completionPrefix('http://{{ho}}', 13), isNull);
      expect(completionPrefix('plain', 5), isNull);
      final r = applyCompletion('http://{{ho}}/p', 11, 'host');
      expect(r.text, 'http://{{host}}/p');
      expect(r.caret, 15);
    });

    test('bulk edit round trip keeps disabled rows', () {
      final rows = parseBulk('A: 1\n// B: two: parts\n\nC');
      expect(rows.map((r) => (r.key, r.value, r.enabled)), [
        ('A', '1', true),
        ('B', 'two: parts', false),
        ('C', '', true),
      ]);
      expect(parseBulk(formatBulk(rows)).length, 3);
    });

    test('suggestions prefer prefixes and skip exact matches', () {
      expect(matchSuggestions(headerNames, 'content-t'), ['Content-Type']);
      expect(
        matchSuggestions(headerNames, 'Accept'),
        isNot(contains('Accept')),
      );
      expect(matchSuggestions(headerNames, ''), isEmpty);
    });

    test('auto headers skip names the request sets', () {
      final item = HttpRequestItem(
        id: 'r',
        name: 'r',
        url: 'https://api.test/x',
        body: const RawBody(RawBodyLanguage.json, '{}'),
        headers: const [KeyValue(key: 'user-agent', value: 'mine')],
      );
      final names = autoHeaders(
        item,
        const BearerAuth(token: 't'),
      ).map((h) => h.$1);
      expect(names, containsAll(['Host', 'Content-Type', 'Authorization']));
      expect(names, isNot(contains('User-Agent')));
    });

    test('sent body is masked and capped', () {
      final m = Masker(secretValues: ['s3cret']);
      final out = describeSentBody('{"k":"s3cret"}'.codeUnits, m);
      expect(out, isNot(contains('s3cret')));
      expect(describeSentBody(const [], m), '');
      expect(
        describeSentBody(List.filled(10, 65), m, cap: 4),
        'AAAA\n… 6 more bytes not shown',
      );
    });
  });

  testWidgets('bulk edit rewrites rows', (tester) async {
    List<KeyValue> rows = const [KeyValue(key: 'a', value: '1')];
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: StatefulBuilder(
            builder: (c, set) => KeyValueEditor(
              rows: rows,
              onChanged: (r) => set(() => rows = r),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.byKey(const Key('kv-bulk-toggle')));
    await tester.pump();
    await tester.enterText(find.byKey(const Key('kv-bulk')), 'x: 1\n// y: 2');
    expect(rows.map((r) => (r.key, r.enabled)), [('x', true), ('y', false)]);
  });

  testWidgets('typing {{ offers variables and picking completes', (
    tester,
  ) async {
    var text = '';
    await tester.pumpWidget(
      MaterialApp(
        home: VariableContext(
          scopes: () => VariableScopes(
            environment: const [
              Variable(key: 'host', value: 'api.test'),
              Variable(key: 'tok', value: 'zzz', secret: true),
            ],
          ),
          child: Scaffold(
            body: StatefulBuilder(
              builder: (c, set) => SyncedTextField(
                value: text,
                variables: true,
                onChanged: (v) => set(() => text = v),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.byType(TextField));
    await tester.enterText(find.byType(TextField), 'http://{{ho');
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('suggest-host')));
    await tester.pump();
    expect(text, 'http://{{host}}');
    await tester.pump();
    expect(find.byKey(const Key('var-info')), findsOneWidget);
    expect(find.textContaining('host = api.test'), findsOneWidget);

    await tester.enterText(find.byType(TextField), '{{tok}}');
    await tester.pump();
    expect(find.textContaining('tok = ••••••'), findsOneWidget);
    expect(find.textContaining('zzz'), findsNothing);
  });

  testWidgets('headers tab lists generated headers and suggests names', (
    tester,
  ) async {
    final t = setup();
    await pumpEditor(tester, t.c, t.id);
    await tester.pump();
    await tester.tap(find.text('Headers'));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('auto-headers')), findsOneWidget);
    expect(find.textContaining('Generated headers'), findsOneWidget);
    await tester.tap(find.byKey(const Key('headers-add')));
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('headers-key-0')));
    await tester.enterText(
      find.byKey(const ValueKey('headers-key-0')),
      'content-t',
    );
    await tester.pump();
    expect(find.byKey(const ValueKey('suggest-Content-Type')), findsOneWidget);
    await tester.pump(EditorNotifier.saveDelay);
  });
}
