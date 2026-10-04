import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:postit_app/src/state/editor_state.dart';
import 'package:postit_app/src/state/session.dart';
import 'package:postit_app/src/state/variables.dart';
import 'package:postit_app/src/widgets/request_editor.dart';
import 'package:postit_core/postit_core.dart';
import 'package:postit_http/postit_http.dart';
import 'package:postit_storage/postit_storage.dart';

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
      httpVersion: 'HTTP/1.1',
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
    await n.send();
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
