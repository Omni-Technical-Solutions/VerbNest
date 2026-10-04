import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:postit_app/src/scripting/script_engine.dart';
import 'package:postit_app/src/scripting/script_flow.dart';
import 'package:postit_app/src/scripting/script_io.dart';
import 'package:postit_app/src/state/editor_state.dart';
import 'package:postit_app/src/state/session.dart';
import 'package:postit_core/postit_core.dart';
import 'package:postit_storage/postit_storage.dart';

import 'editor_test.dart' show FakeEngine;

class FakeScripts implements ScriptEngine {
  FakeScripts(this.handler);

  final ScriptOutput Function(ScriptInput) handler;
  final inputs = <ScriptInput>[];

  @override
  Future<ScriptOutput> run(
    ScriptInput input, {
    Duration timeout = defaultScriptTimeout,
  }) async {
    inputs.add(input);
    return handler(input);
  }
}

typedef Env = ({
  ProviderContainer c,
  WorkspaceSession s,
  FakeEngine http,
  FakeScripts js,
  String col,
  String folder,
  String id,
});

Env setup(ScriptOutput Function(ScriptInput) handler) {
  final s = WorkspaceSession.memory();
  final http = FakeEngine();
  final js = FakeScripts(handler);
  final c = ProviderContainer(
    overrides: [
      sessionProvider.overrideWithValue(s),
      engineProvider.overrideWithValue(http),
      scriptEngineProvider.overrideWithValue(js),
    ],
  );
  final col = s.repo.createCollection('C');
  final folder = s.repo.createFolder(col, 'F');
  final id = s.repo.createRequest(
    folder,
    HttpRequestItem(
      id: '',
      name: 'R',
      url: 'http://x.test/a',
      scripts: const Scripts(pre: 'req-pre', post: 'req-post'),
    ),
  );
  addTearDown(() {
    c.dispose();
    s.close();
  });
  return (c: c, s: s, http: http, js: js, col: col, folder: folder, id: id);
}

void main() {
  group('script source and output', () {
    test('user code is embedded as a string, not spliced into the runtime', () {
      const code = "a\n'\"\u2028\${x}\\";
      final src = const ScriptInput(
        code: code,
        phase: ScriptPhase.pre,
        requestName: 'R',
        requestId: 'i',
        request: {'method': 'GET', 'url': 'u', 'headers': [], 'body': ''},
      ).toSource();
      final tail = src.substring(src.lastIndexOf('__run('));
      expect(tail, contains(jsonEncode(code)));
      expect(tail.endsWith(');'), isTrue);
    });

    test('output decodes tests, logs, changes and the request', () {
      final o = ScriptOutput.fromJson(
        jsonEncode({
          'tests': [
            {'name': 'a', 'status': 'pass'},
            {'name': 'b', 'status': 'fail', 'message': 'nope'},
          ],
          'logs': [
            {'level': 'warn', 'text': 'hi'},
          ],
          'changes': {
            'environment': {'k': 'v', 'gone': null},
          },
          'request': {'method': 'POST'},
          'error': null,
        }),
        elapsed: const Duration(milliseconds: 4),
      );
      expect(o.ok, isTrue);
      expect(o.tests.map((t) => t.failed), [false, true]);
      expect(o.logs.single.level, 'warn');
      final env = o.changes[ScriptScope.environment]!;
      expect(env.map((c) => (c.key, c.value)), [('k', 'v'), ('gone', null)]);
      expect(o.request!['method'], 'POST');
    });
  });

  group('running scripts for a request', () {
    test('collection, folder then request scripts run in order', () async {
      final t = setup((_) => const ScriptOutput());
      t.s.repo.setContainerScripts(t.col, const Scripts(pre: 'col-pre'));
      t.s.repo.setContainerScripts(t.folder, const Scripts(pre: 'folder-pre'));
      final item = t.s.repo.getRequest(t.id);
      await runScriptPhase(
        session: t.s,
        engine: t.js,
        requestId: t.id,
        item: item,
        envId: null,
        phase: ScriptPhase.pre,
        request: requestToMap(item),
      );
      expect(t.js.inputs.map((i) => i.code), [
        'col-pre',
        'folder-pre',
        'req-pre',
      ]);
    });

    test('the first error stops later scripts', () async {
      final t = setup(
        (i) => i.code == 'col-pre'
            ? ScriptOutput.failed('boom')
            : const ScriptOutput(),
      );
      t.s.repo.setContainerScripts(t.col, const Scripts(pre: 'col-pre'));
      final item = t.s.repo.getRequest(t.id);
      final r = await runScriptPhase(
        session: t.s,
        engine: t.js,
        requestId: t.id,
        item: item,
        envId: null,
        phase: ScriptPhase.pre,
        request: requestToMap(item),
      );
      expect(r.error, 'boom');
      expect(t.js.inputs, hasLength(1));
    });

    test('variable changes become current values and new variables', () async {
      final t = setup((_) => const ScriptOutput());
      const env = 'env1';
      t.s.repo.saveEnvironment(
        const Environment(
          id: env,
          name: 'dev',
          variables: [
            Variable(key: 'host', value: 'initial'),
            Variable(key: 'gone', value: '1'),
          ],
        ),
      );
      t.s.repo.saveVariables(VariableOwner.global, [
        const Variable(key: 'g', value: '1'),
      ]);
      final js = FakeScripts(
        (_) => const ScriptOutput(
          changes: {
            ScriptScope.environment: [
              VariableChange('host', 'changed'),
              VariableChange('gone', null),
              VariableChange('fresh', 'x'),
            ],
            ScriptScope.collection: [VariableChange('n', '5')],
            ScriptScope.globals: [VariableChange('g', '2')],
            ScriptScope.local: [VariableChange('tmp', 't')],
          },
        ),
      );
      final item = t.s.repo.getRequest(t.id);
      final r = await runScriptPhase(
        session: t.s,
        engine: js,
        requestId: t.id,
        item: item,
        envId: env,
        phase: ScriptPhase.pre,
        request: requestToMap(item),
      );
      final vars = {
        for (final v in t.s.repo.variables(VariableOwner.environment(env)))
          v.key: v.value,
      };
      expect(vars, {'host': 'initial', 'fresh': 'x'});
      expect(
        t.s.currentOverrides('environment', env),
        containsPair('host', 'changed'),
      );
      expect(
        t.s.repo.variables(VariableOwner.collection(t.col)).single.value,
        '5',
      );
      expect(t.s.currentOverrides('global', '')['g'], '2');
      expect(r.local, {'tmp': 't'});
    });

    test(
      'scripts see current values and later scripts see earlier changes',
      () async {
        final t = setup((i) {
          if (i.code == 'col-post') {
            return const ScriptOutput(
              changes: {
                ScriptScope.collection: [VariableChange('seen', 'yes')],
              },
            );
          }
          return const ScriptOutput();
        });
        t.s.repo.setContainerScripts(t.col, const Scripts(post: 'col-post'));
        final item = t.s.repo.getRequest(t.id);
        await runScriptPhase(
          session: t.s,
          engine: t.js,
          requestId: t.id,
          item: item,
          envId: null,
          phase: ScriptPhase.post,
          request: requestToMap(item),
        );
        final last = t.js.inputs.last;
        expect(last.code, 'req-post');
        expect(last.variables[ScriptScope.collection], {'seen': 'yes'});
      },
    );
  });

  group('request round trip', () {
    test('script edits to headers, method, url and body are applied', () {
      const item = HttpRequestItem(
        id: 'i',
        name: 'R',
        url: 'http://x.test/a',
        headers: [
          KeyValue(key: 'A', value: '1'),
          KeyValue(key: 'Off', value: '2', enabled: false),
        ],
        body: RawBody(RawBodyLanguage.json, '{}'),
      );
      final map = requestToMap(item);
      expect((map['headers'] as List).length, 1);
      final out = applyRequestMap(item, {
        'method': 'post',
        'url': 'http://x.test/a?q=1',
        'headers': [
          {'key': 'A', 'value': '9'},
          {'key': 'New', 'value': 'n'},
        ],
        'body': '{"a":1}',
      });
      expect(out.method, 'POST');
      expect(out.params.single.key, 'q');
      expect(out.headers.map((h) => '${h.key}=${h.value}/${h.enabled}'), [
        'A=9/true',
        'New=n/true',
        'Off=2/false',
      ]);
      expect((out.body as RawBody).text, '{"a":1}');
      expect((out.body as RawBody).language, RawBodyLanguage.json);
    });
  });

  group('sending with scripts', () {
    test('pre-request changes reach the wire; tests are kept', () async {
      final t = setup((i) {
        if (i.phase == ScriptPhase.pre) {
          return ScriptOutput(
            request: {
              'method': 'PUT',
              'url': 'http://x.test/b',
              'headers': [
                {'key': 'X-S', 'value': '1'},
              ],
              'body': '',
            },
            changes: const {
              ScriptScope.local: [VariableChange('who', 'me')],
            },
            logs: const [ConsoleLine('log', 'pre ran')],
          );
        }
        return const ScriptOutput(
          tests: [
            TestResult(name: 'ok', status: 'pass'),
            TestResult(name: 'bad', status: 'fail', message: 'x'),
          ],
        );
      });
      final n = t.c.read(editorProvider(t.id).notifier);
      await n.send(force: true);
      expect(t.http.last!.method, 'PUT');
      expect(t.http.last!.url.path, '/b');
      expect(t.http.last!.headers.map((h) => h.$1), contains('X-S'));
      final st = t.c.read(editorProvider(t.id));
      expect(st.tests.map((x) => x.name), ['ok', 'bad']);
      expect(st.scriptLogs.single.text, 'pre ran');
      expect(st.response!.status, 201);
      expect(st.scriptError, isNull);
      // The draft the user typed is not rewritten by the script.
      expect(st.item.url, 'http://x.test/a');
    });

    test('a failing pre-request script stops the send', () async {
      final t = setup((i) => ScriptOutput.failed('bad pre'));
      final n = t.c.read(editorProvider(t.id).notifier);
      await n.send(force: true);
      expect(t.http.last, isNull);
      expect(
        t.c.read(editorProvider(t.id)).error,
        'Pre-request script failed: bad pre',
      );
    });

    test('a failing post-response script keeps the response', () async {
      final t = setup(
        (i) => i.phase == ScriptPhase.post
            ? ScriptOutput.failed('bad post')
            : const ScriptOutput(),
      );
      final n = t.c.read(editorProvider(t.id).notifier);
      await n.send(force: true);
      final st = t.c.read(editorProvider(t.id));
      expect(st.response!.status, 201);
      expect(st.scriptError, 'bad post');
    });

    test('requests without scripts never call the engine', () async {
      final t = setup((_) => const ScriptOutput());
      t.s.repo.saveRequest(
        HttpRequestItem(id: t.id, name: 'R', url: 'http://x.test/a'),
      );
      final n = t.c.read(editorProvider(t.id).notifier);
      n.edit((i) => i.copyWith(scripts: const Scripts()));
      await n.send(force: true);
      expect(t.js.inputs, isEmpty);
    });
  });
}
