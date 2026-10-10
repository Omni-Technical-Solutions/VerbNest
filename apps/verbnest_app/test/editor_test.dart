import 'dart:convert';
import 'dart:typed_data';

import 'package:material_ui/material_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:verbnest_app/src/state/editor_state.dart';
import 'package:verbnest_app/src/state/session.dart';
import 'package:verbnest_app/src/state/variables.dart';
import 'package:verbnest_app/src/widgets/request_editor.dart';
import 'package:verbnest_core/verbnest_core.dart';
import 'package:verbnest_http/verbnest_http.dart';
import 'package:verbnest_storage/verbnest_storage.dart';

class FakeEngine extends HttpEngine {
  HttpRequestSpec? last;
  Object? failWith;

  @override
  Future<HttpResponseRecord> send(
    HttpRequestSpec spec, {
    CancelToken? cancel,
  }) async {
    last = spec;
    if (failWith != null) throw failWith!;
    final body = Uint8List.fromList(utf8.encode('{"ok":true}'));
    const zero = Duration.zero;
    return HttpResponseRecord(
      status: 201,
      reason: 'Created',
      httpVersion: '1.1',
      headers: [('Content-Type', 'application/json')],
      body: body,
      wireBodySize: body.length,
      timings: const Timings(
        dns: zero,
        connect: zero,
        tls: zero,
        ttfb: zero,
        download: zero,
        total: Duration(milliseconds: 12),
      ),
      finalUrl: spec.url,
      sent: SentRequest(
        head: 'GET / HTTP/1.1\r\nAuthorization: Bearer s3cret\r\n\r\n',
        body: Uint8List(0),
        url: spec.url,
      ),
    );
  }
}

({ProviderContainer c, WorkspaceSession s, FakeEngine e, String id}) setup() {
  final s = WorkspaceSession.memory();
  final e = FakeEngine();
  final c = ProviderContainer(
    overrides: [
      sessionProvider.overrideWithValue(s),
      engineProvider.overrideWithValue(e),
    ],
  );
  final col = s.repo.createCollection('C');
  final id = s.repo.createRequest(col, HttpRequestItem(id: '', name: 'R'));
  addTearDown(() {
    c.dispose();
    s.close();
  });
  return (c: c, s: s, e: e, id: id);
}

void main() {
  oauthTests();
  envAndHistoryTests();
  test('edits are saved after the debounce and name is kept', () async {
    final t = setup();
    final n = t.c.read(editorProvider(t.id).notifier);
    n.edit((i) => i.copyWith(url: 'http://x.test/a'));
    t.s.repo.rename(t.id, 'Renamed');
    expect(t.s.repo.getRequest(t.id).url, '');
    await Future<void>.delayed(
      EditorNotifier.saveDelay + const Duration(milliseconds: 100),
    );
    final saved = t.s.repo.getRequest(t.id);
    expect(saved.url, 'http://x.test/a');
    expect(saved.name, 'Renamed');
  });

  test('send resolves variables, reports unresolved, masks head', () async {
    final t = setup();
    final col = t.s.repo.ancestors(t.id).single;
    t.s.repo.saveVariables(VariableOwner.collection(col), [
      const Variable(key: 'host', value: 'api.test'),
    ]);
    final n = t.c.read(editorProvider(t.id).notifier);
    n.edit(
      (i) => i.copyWith(
        url: 'http://{{host}}/u/:id?q={{missing}}',
        auth: const BearerAuth(token: 's3cret'),
      ),
    );
    await n.send(force: true);
    final spec = t.e.last!;
    expect(spec.url.host, 'api.test');
    final st = t.c.read(editorProvider(t.id));
    expect(st.response!.status, 201);
    expect(st.unresolved, {'missing'});
    expect(t.s.repo.getRequest(t.id).url, contains('{{host}}'));
  });

  test('send reports build and engine errors', () async {
    final t = setup();
    final n = t.c.read(editorProvider(t.id).notifier);
    await n.send();
    expect(t.c.read(editorProvider(t.id)).error, contains('URL'));
    n.edit((i) => i.copyWith(url: 'http://x.test'));
    t.e.failWith = const TimeoutError('Timed out');
    await n.send();
    final st = t.c.read(editorProvider(t.id));
    expect(st.error, 'Timed out');
    expect(st.sending, false);
  });

  testWidgets('pasting a cURL command into the URL bar fills the request', (
    tester,
  ) async {
    final t = setup();
    tester.view.physicalSize = const Size(1000, 1000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: t.c,
        child: MaterialApp(
          home: Scaffold(body: RequestEditor(requestId: t.id)),
        ),
      ),
    );
    await tester.enterText(
      find.byKey(const Key('url')),
      "curl -X POST 'http://x.test/a?q=1' -H 'X-A: b'",
    );
    await tester.pump();
    final item = t.c.read(editorProvider(t.id)).item;
    expect(item.method, 'POST');
    expect(item.url, startsWith('http://x.test/a'));
    expect(item.headers.map((h) => h.key), contains('X-A'));
    await tester.pump(EditorNotifier.saveDelay);
  });

  testWidgets('url and params table stay in sync; send shows response', (
    tester,
  ) async {
    final t = setup();
    tester.view.physicalSize = const Size(1000, 1000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: t.c,
        child: MaterialApp(
          home: Scaffold(body: RequestEditor(requestId: t.id)),
        ),
      ),
    );
    await tester.enterText(
      find.byKey(const Key('url')),
      'http://x.test/p/:id?a=1&b=2',
    );
    await tester.pump();
    final item = t.c.read(editorProvider(t.id)).item;
    expect(item.params.map((p) => p.key), ['a', 'b']);
    expect(item.pathVars.single.key, 'id');
    expect(find.byKey(const ValueKey('params-key-0')), findsOneWidget);

    await tester.enterText(find.byKey(const ValueKey('params-value-0')), '9');
    await tester.pump();
    expect(
      t.c.read(editorProvider(t.id)).item.url,
      'http://x.test/p/:id?a=9&b=2',
    );

    await tester.tap(find.byKey(const Key('send')));
    await tester.pump();
    await tester.pump();
    expect(find.byKey(const Key('response-status')), findsOneWidget);
    expect(find.text('201 Created'), findsOneWidget);
    await tester.pump(EditorNotifier.saveDelay);
  });
}

void envAndHistoryTests() {
  test('environment values and secrets resolve; history is masked', () async {
    final t = setup();
    final repo = t.s.repo;
    repo.saveEnvironment(const Environment(id: 'E1', name: 'Dev'));
    saveVariables(t.s, VariableOwner.environment('E1'), [
      const Variable(key: 'host', value: 'dev.test'),
      const Variable(key: 'tok', value: 's3cret', secret: true),
    ]);
    // Secret value is not in the workspace file.
    expect(repo.variables(VariableOwner.environment('E1')).last.value, isEmpty);
    expect(
      loadVariables(t.s, VariableOwner.environment('E1')).last.value,
      's3cret',
    );

    t.c.read(activeEnvProvider.notifier).select('E1');
    expect(repo.defaultEnvironmentId, 'E1');

    final n = t.c.read(editorProvider(t.id).notifier);
    n.edit(
      (i) => i.copyWith(
        url: 'http://{{host}}/x',
        auth: const BearerAuth(token: '{{tok}}'),
      ),
    );
    await n.send();
    // The secret may not go to a host nobody approved for it.
    expect(t.e.last, isNull);
    final pending = t.c.read(editorProvider(t.id)).pendingSecretHost!;
    expect(pending.names, ['tok']);
    expect(pending.host, 'dev.test');
    await n.approveSecretHostAndSend();
    expect(t.c.read(editorProvider(t.id)).pendingSecretHost, isNull);
    expect(t.e.last!.url.host, 'dev.test');
    expect(t.e.last!.headers.any((h) => h.$2.contains('s3cret')), isTrue);

    final history = t.s.local.listHistory(repo.workspaceId);
    expect(history, hasLength(1));
    expect(history.single.environmentName, 'Dev');
    expect(history.single.status, 201);
    expect(history.single.requestJson, isNot(contains('s3cret')));
  });

  test('engine failures are recorded in history', () async {
    final t = setup();
    final n = t.c.read(editorProvider(t.id).notifier);
    n.edit((i) => i.copyWith(url: 'http://x.test'));
    t.e.failWith = const NetworkError('refused');
    await n.send();
    final h = t.s.local.listHistory(t.s.repo.workspaceId).single;
    expect(h.error, 'refused');
    expect(h.status, isNull);
  });
}

void oauthTests() {
  test('OAuth2 fetches a token once and sends it as bearer', () async {
    final t = setup();
    final calls = <String>[];
    final engine = _TokenEngine(calls);
    final c = ProviderContainer(
      overrides: [
        sessionProvider.overrideWithValue(t.s),
        engineProvider.overrideWithValue(engine),
      ],
    );
    addTearDown(c.dispose);
    final n = c.read(editorProvider(t.id).notifier);
    n.edit(
      (i) => i.copyWith(
        url: 'http://api.test/x',
        auth: const OAuth2Auth(
          grant: OAuth2Grant.clientCredentials,
          tokenUrl: 'http://auth.test/token',
          clientId: 'id',
          clientSecret: 'sec',
        ),
      ),
    );
    await n.send();
    await n.send();
    expect(calls.where((u) => u.contains('auth.test')), hasLength(1));
    final api = engine.apiSpecs.last;
    expect(
      api.headers.firstWhere((h) => h.$1 == 'Authorization').$2,
      'Bearer T0K',
    );
    expect(c.read(editorProvider(t.id)).response!.status, 200);
  });

  testWidgets('auth and assertions tabs render in the request editor', (
    tester,
  ) async {
    final t = setup();
    tester.view.physicalSize = const Size(1000, 1000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: t.c,
        child: MaterialApp(
          home: Scaffold(body: RequestEditor(requestId: t.id)),
        ),
      ),
    );
    await tester.tap(find.text('Auth'));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    expect(find.byKey(const Key('auth-type')), findsOneWidget);

    await tester.tap(find.text('Assertions'));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    expect(find.byKey(const Key('add-assertion')), findsOneWidget);
    await tester.pump(EditorNotifier.saveDelay);
  });
}

class _TokenEngine extends HttpEngine {
  _TokenEngine(this.calls);

  final List<String> calls;
  final apiSpecs = <HttpRequestSpec>[];

  @override
  Future<HttpResponseRecord> send(
    HttpRequestSpec spec, {
    CancelToken? cancel,
  }) async {
    calls.add(spec.url.toString());
    final isToken = spec.url.host == 'auth.test';
    if (!isToken) apiSpecs.add(spec);
    final body = Uint8List.fromList(
      utf8.encode(isToken ? '{"access_token":"T0K","expires_in":3600}' : '{}'),
    );
    const z = Duration.zero;
    return HttpResponseRecord(
      status: 200,
      reason: 'OK',
      httpVersion: '1.1',
      headers: const [],
      body: body,
      wireBodySize: body.length,
      timings: const Timings(
        dns: z,
        connect: z,
        tls: z,
        ttfb: z,
        download: z,
        total: z,
      ),
      finalUrl: spec.url,
      sent: SentRequest(head: 'x', body: Uint8List(0), url: spec.url),
    );
  }
}
