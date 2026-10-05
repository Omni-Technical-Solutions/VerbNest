import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:postit_app/src/state/editor_state.dart';
import 'package:postit_app/src/state/file_port.dart';
import 'package:postit_app/src/state/graphql_state.dart';
import 'package:postit_app/src/state/session.dart';
import 'package:postit_app/src/widgets/graphql_editor.dart';
import 'package:postit_core/postit_core.dart';
import 'package:postit_http/postit_http.dart';
import 'package:postit_storage/postit_storage.dart';

import 'editor_test.dart' show FakeEngine;
import 'step12_test.dart' show FakePort, mount;

const _sdl = '''
type Query { me: User  users(first: Int): [User!]! }
type User { id: ID! name: String friends: [User!]! }
''';

/// Answers every request with [answer] as JSON.
class GraphqlEngine extends FakeEngine {
  GraphqlEngine(this.answer);

  Object? answer;

  @override
  Future<HttpResponseRecord> send(
    HttpRequestSpec spec, {
    CancelToken? cancel,
  }) async {
    final r = await super.send(spec, cancel: cancel);
    final body = Uint8List.fromList(utf8.encode(jsonEncode(answer)));
    return HttpResponseRecord(
      status: 200,
      reason: 'OK',
      httpVersion: '1.1',
      headers: r.headers,
      body: body,
      wireBodySize: body.length,
      timings: r.timings,
      finalUrl: r.finalUrl,
      sent: r.sent,
    );
  }
}

Map<String, Object?> _introspectionFor(String sdl) {
  final schema = GraphqlSchema.fromSdl(sdl);
  Map<String, Object?> ref(String type) {
    var t = type;
    if (t.endsWith('!')) {
      return {
        'kind': 'NON_NULL',
        'name': null,
        'ofType': ref(t.substring(0, t.length - 1)),
      };
    }
    if (t.startsWith('[')) {
      return {
        'kind': 'LIST',
        'name': null,
        'ofType': ref(t.substring(1, t.length - 1)),
      };
    }
    return {'kind': 'OBJECT', 'name': t, 'ofType': null};
  }

  return {
    'data': {
      '__schema': {
        'queryType': {'name': 'Query'},
        'types': [
          for (final t in schema.types.values)
            {
              'kind': t.kind == GqlKind.scalar ? 'SCALAR' : 'OBJECT',
              'name': t.name,
              'fields': [
                for (final f in t.fields)
                  {
                    'name': f.name,
                    'isDeprecated': false,
                    'args': [
                      for (final a in f.args)
                        {'name': a.name, 'type': ref(a.type)},
                    ],
                    'type': ref(f.type),
                  },
              ],
              'interfaces': <Object?>[],
            },
        ],
      },
    },
  };
}

({
  ProviderContainer c,
  WorkspaceSession s,
  GraphqlEngine e,
  FakePort p,
  String id,
})
setup({Object? answer}) {
  final s = WorkspaceSession.memory();
  final e = GraphqlEngine(answer ?? _introspectionFor(_sdl));
  final p = FakePort();
  final c = ProviderContainer(
    overrides: [
      sessionProvider.overrideWithValue(s),
      engineProvider.overrideWithValue(e),
      filePortProvider.overrideWithValue(p),
    ],
  );
  final col = s.repo.createCollection('C');
  final id = s.repo.createRequest(
    col,
    HttpRequestItem(id: '', name: 'R', url: 'http://x.test/graphql'),
  );
  addTearDown(() {
    c.dispose();
    s.close();
  });
  return (c: c, s: s, e: e, p: p, id: id);
}

Future<void> openGraphql(
  WidgetTester tester,
  ProviderContainer c,
  String id,
) async {
  await mount(tester, c, id);
  await tester.tap(find.text('Body'));
  await tester.pumpAndSettle();
  await tester.tap(find.byKey(const Key('body-mode')));
  await tester.pumpAndSettle();
  await tester.tap(find.text('graphql').last);
  await tester.pumpAndSettle();
}

void main() {
  test('send posts the operation as JSON with variables resolved', () async {
    final t = setup();
    final col = t.s.repo.ancestors(t.id).single;
    t.s.repo.saveVariables(VariableOwner.collection(col), [
      const Variable(key: 'uid', value: '42'),
    ]);
    final n = t.c.read(editorProvider(t.id).notifier);
    n.edit(
      (i) => i.copyWith(
        method: 'POST',
        body: const GraphqlBody(
          query: 'query U(\$id: ID!) { user(id: \$id) { name } }',
          variables: '{"id": "{{uid}}"}',
          operationName: 'U',
        ),
      ),
    );
    await n.send(force: true);
    final spec = t.e.last!;
    expect(spec.method, 'POST');
    expect(
      spec.headers.any(
        (h) =>
            h.$1.toLowerCase() == 'content-type' && h.$2 == 'application/json',
      ),
      isTrue,
    );
    final sent = jsonDecode(utf8.decode(spec.body!)) as Map;
    expect(sent['operationName'], 'U');
    expect(sent['variables'], {'id': '42'});
    expect(sent['query'], contains('user(id: \$id)'));
  });

  test('bad variables stop the send with a clear message', () async {
    final t = setup();
    final n = t.c.read(editorProvider(t.id).notifier);
    n.edit(
      (i) => i.copyWith(
        body: const GraphqlBody(query: '{ a }', variables: '{oops'),
      ),
    );
    await n.send(force: true);
    expect(t.c.read(editorProvider(t.id)).error, contains('not valid JSON'));
    expect(t.e.last, isNull);
  });

  test('introspect loads the schema and the store keeps it per URL', () async {
    final t = setup();
    final n = t.c.read(editorProvider(t.id).notifier);
    final schema = await n.introspect();
    expect(schema.type('Query')!.fields.map((f) => f.name), ['me', 'users']);
    expect(schema.type('Query')!.fields.last.type, '[User!]!');
    final sent = jsonDecode(utf8.decode(t.e.last!.body!)) as Map;
    expect(sent['query'], graphqlIntrospectionQuery);
    expect(t.e.last!.method, 'POST');

    const url = 'http://x.test/graphql';
    expect(t.c.read(graphqlSchemaProvider(url)), isNull);
    t.c.read(graphqlSchemaProvider(url).notifier).set(schema);
    expect(t.c.read(graphqlSchemaProvider(url))!.userTypes, hasLength(2));
    t.c.invalidate(graphqlSchemaProvider(url));
    expect(
      t.c.read(graphqlSchemaProvider(url))!.type('User')!.fields,
      hasLength(3),
    );
    expect(t.c.read(graphqlSchemaProvider('http://other.test')), isNull);
  });

  test('introspect explains server errors and non-JSON answers', () async {
    final t = setup(
      answer: {
        'errors': [
          {'message': 'GraphQL introspection is not allowed'},
        ],
      },
    );
    final n = t.c.read(editorProvider(t.id).notifier);
    await expectLater(
      n.introspect(),
      throwsA(
        isA<FormatException>().having(
          (e) => e.message,
          'message',
          contains('introspection is not allowed'),
        ),
      ),
    );
    t.e.failWith = const TimeoutError('Timed out');
    await expectLater(
      n.introspect(),
      throwsA(
        isA<FormatException>().having((e) => e.message, 'message', 'Timed out'),
      ),
    );
  });

  testWidgets('choosing graphql switches GET to POST and edits are stored', (
    tester,
  ) async {
    final t = setup();
    await openGraphql(tester, t.c, t.id);
    expect(find.byKey(const Key('gql-query')), findsOneWidget);
    await tester.enterText(find.byKey(const Key('gql-query')), '{ me { id } }');
    await tester.enterText(find.byKey(const Key('gql-variables')), '{"a": 1}');
    await tester.pump();
    final item = t.c.read(editorProvider(t.id)).item;
    expect(item.method, 'POST');
    final body = item.body as GraphqlBody;
    expect(body.query, '{ me { id } }');
    expect(body.variables, '{"a": 1}');
    expect(find.byKey(const Key('gql-operation')), findsNothing);
    await tester.pump(EditorNotifier.saveDelay);
  });

  testWidgets('the persisted-query chip is stored on the body', (tester) async {
    final t = setup();
    await openGraphql(tester, t.c, t.id);
    await tester.tap(find.byKey(const Key('gql-persisted')));
    await tester.pump();
    expect(
      (t.c.read(editorProvider(t.id)).item.body as GraphqlBody).persisted,
      isTrue,
    );
    await tester.pump(EditorNotifier.saveDelay);
  });

  testWidgets('import SDL enables completion and the explorer', (tester) async {
    final t = setup();
    await openGraphql(tester, t.c, t.id);
    expect(find.text('No schema loaded'), findsOneWidget);

    await tester.tap(find.byKey(const Key('gql-import-sdl')));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const Key('gql-sdl-text')), _sdl);
    await tester.tap(find.byKey(const Key('gql-sdl-ok')));
    await tester.pumpAndSettle();
    expect(find.text('2 types'), findsOneWidget);

    // Completion chips follow the caret inside a selection set.
    await tester.tap(find.byKey(const Key('gql-query')));
    await tester.enterText(find.byKey(const Key('gql-query')), '{ me { ');
    await tester.pump();
    expect(find.byKey(const ValueKey('suggest-friends')), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('suggest-friends')));
    await tester.pump();
    expect(
      (t.c.read(editorProvider(t.id)).item.body as GraphqlBody).query,
      '{ me { friends {',
    );

    await tester.tap(find.byKey(const Key('gql-explore')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('gql-root-Query')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('gql-detail')), findsOneWidget);
    expect(find.text('[User!]!'), findsOneWidget);
    await tester.tap(find.text('[User!]!'));
    await tester.pumpAndSettle();
    expect(find.text('friends'), findsOneWidget);
    await tester.tap(find.byKey(const Key('gql-back')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('gql-back')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('gql-root')), findsOneWidget);
  });

  testWidgets('a bad SDL is reported and keeps the old state', (tester) async {
    final t = setup();
    await openGraphql(tester, t.c, t.id);
    await tester.tap(find.byKey(const Key('gql-import-sdl')));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const Key('gql-sdl-text')), 'type A {');
    await tester.tap(find.byKey(const Key('gql-sdl-ok')));
    await tester.pumpAndSettle();
    expect(find.textContaining('Could not read the schema'), findsOneWidget);
    expect(find.text('No schema loaded'), findsOneWidget);
  });

  testWidgets('fetch schema loads it through the request URL', (tester) async {
    final t = setup();
    await openGraphql(tester, t.c, t.id);
    await tester.tap(find.byKey(const Key('gql-fetch')));
    await tester.pumpAndSettle();
    expect(find.text('2 types'), findsOneWidget);
  });

  testWidgets('several operations offer an operation picker', (tester) async {
    final t = setup();
    await openGraphql(tester, t.c, t.id);
    await tester.enterText(
      find.byKey(const Key('gql-query')),
      'query A { me { id } } query B { me { name } }',
    );
    await tester.pump();
    expect(find.byKey(const Key('gql-operation')), findsOneWidget);
    await tester.pump(EditorNotifier.saveDelay);
  });

  testWidgets('explorer filters types by name', (tester) async {
    final schema = GraphqlSchema.fromSdl(_sdl);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(body: GraphqlExplorer(schema: schema)),
      ),
    );
    expect(find.byKey(const Key('gql-type-User')), findsOneWidget);
    await tester.enterText(find.byKey(const Key('gql-type-filter')), 'quer');
    await tester.pump();
    expect(find.byKey(const Key('gql-type-User')), findsNothing);
    expect(find.byKey(const Key('gql-type-Query')), findsOneWidget);
  });
}
