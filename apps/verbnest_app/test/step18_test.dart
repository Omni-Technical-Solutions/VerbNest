import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:verbnest_app/src/scripting/script_engine.dart';
import 'package:verbnest_app/src/scripting/script_io.dart';
import 'package:verbnest_app/src/state/editor_state.dart';
import 'package:verbnest_app/src/state/runner.dart';
import 'package:verbnest_app/src/state/session.dart';
import 'package:verbnest_core/verbnest_core.dart';

import 'editor_test.dart' show FakeEngine;
import 'step17_test.dart' show FakeScripts;

typedef Env = ({
  ProviderContainer c,
  WorkspaceSession s,
  FakeEngine http,
  String col,
});

Env setup([ScriptOutput Function(ScriptInput)? scripts]) {
  final s = WorkspaceSession.memory();
  s.local.setKv(s.repo.workspaceId, 'pref.scriptsTrusted', 'true');
  final http = FakeEngine();
  final c = ProviderContainer(
    overrides: [
      sessionProvider.overrideWithValue(s),
      engineProvider.overrideWithValue(http),
      scriptEngineProvider.overrideWithValue(
        FakeScripts(scripts ?? (_) => const ScriptOutput()),
      ),
    ],
  );
  final col = s.repo.createCollection('C');
  addTearDown(() {
    c.dispose();
    s.close();
  });
  return (c: c, s: s, http: http, col: col);
}

String add(
  Env t,
  String name, {
  String url = 'http://x.test/a',
  List<Assertion> assertions = const [],
  Scripts scripts = const Scripts(),
}) => t.s.repo.createRequest(
  t.col,
  HttpRequestItem(
    id: '',
    name: name,
    url: url,
    assertions: assertions,
    scripts: scripts,
  ),
);

void main() {
  group('assertions in the send flow', () {
    test('results join the Tests list, failing ones carry a message', () async {
      final t = setup();
      final id = add(
        t,
        'R',
        assertions: const [
          Assertion(target: AssertionTarget.status, value: '201'),
          Assertion(
            target: AssertionTarget.jsonPath,
            name: r'$.ok',
            value: 'false',
          ),
          Assertion(
            target: AssertionTarget.status,
            value: '500',
            enabled: false,
          ),
        ],
      );
      await t.c.read(editorProvider(id).notifier).send();
      final tests = t.c.read(editorProvider(id)).tests;
      expect(tests.map((x) => x.status), ['pass', 'fail']);
      expect(tests[1].message, contains('true'));
    });

    test('values may use variables', () async {
      final t = setup();
      final id = add(
        t,
        'R',
        assertions: const [
          Assertion(target: AssertionTarget.status, value: '{{want}}'),
        ],
      );
      await t.c
          .read(editorProvider(id).notifier)
          .send(data: const {'want': '201'});
      expect(t.c.read(editorProvider(id)).tests.single.passed, isTrue);
    });
  });

  group('collection runner', () {
    test('runs every request once per data row with the row as data', () async {
      final t = setup();
      final a = add(t, 'A', url: 'http://x.test/{{user}}');
      final b = add(t, 'B', url: 'http://x.test/b/{{user}}');
      final report = await t.c
          .read(runnerProvider.notifier)
          .run(
            RunConfig(
              name: 'C',
              requestIds: [a, b],
              data: const [
                {'user': 'ann'},
                {'user': 'bob'},
              ],
            ),
          );
      expect(report.iterations, 2);
      expect(report.entries.map((e) => (e.iteration, e.name)), [
        (1, 'A'),
        (1, 'B'),
        (2, 'A'),
        (2, 'B'),
      ]);
      expect(t.http.last!.url.path, '/b/bob');
      expect(report.ok, isTrue);
      expect(t.c.read(runnerProvider).report, isNotNull);
    });

    test('stop on first failure ends the run', () async {
      final t = setup();
      const failing = [Assertion(target: AssertionTarget.status, value: '1')];
      final a = add(t, 'A', assertions: failing);
      final b = add(t, 'B');
      final all = await t.c
          .read(runnerProvider.notifier)
          .run(RunConfig(name: 'C', requestIds: [a, b]));
      expect(all.entries.length, 2);
      expect(all.failedTests, 1);

      final stopped = await t.c
          .read(runnerProvider.notifier)
          .run(RunConfig(name: 'C', requestIds: [a, b], stopOnFailure: true));
      expect(stopped.entries.length, 1);
      expect(stopped.stoppedEarly, isTrue);
    });

    test('the order given is the order run, repeated by iterations', () async {
      final t = setup();
      final a = add(t, 'A');
      final b = add(t, 'B');
      final r = await t.c
          .read(runnerProvider.notifier)
          .run(RunConfig(name: 'C', requestIds: [b, a], iterations: 2));
      expect(r.entries.map((e) => e.name), ['B', 'A', 'B', 'A']);
    });

    test('setNextRequest jumps, skipRequest skips', () async {
      final t = setup(
        (i) => switch (i.code) {
          'jump' => const ScriptOutput(flow: ScriptFlow(next: 'C')),
          'skip' => const ScriptOutput(flow: ScriptFlow(skip: true)),
          _ => const ScriptOutput(),
        },
      );
      final a = add(t, 'A', scripts: const Scripts(post: 'jump'));
      final b = add(t, 'B');
      final c = add(t, 'C', scripts: const Scripts(pre: 'skip'));
      final r = await t.c
          .read(runnerProvider.notifier)
          .run(RunConfig(name: 'X', requestIds: [a, b, c]));
      expect(r.entries.map((e) => (e.name, e.skipped)), [
        ('A', false),
        ('C', true),
      ]);
    });

    test('a jump to an unknown name is reported and stops', () async {
      final t = setup((_) => const ScriptOutput(flow: ScriptFlow(next: 'Zed')));
      final a = add(t, 'A', scripts: const Scripts(post: 'x'));
      final r = await t.c
          .read(runnerProvider.notifier)
          .run(RunConfig(name: 'X', requestIds: [a]));
      expect(r.entries.single.error, contains('Zed'));
      expect(r.ok, isFalse);
    });

    test('a request pointing at itself ends at the step limit', () async {
      final t = setup((_) => const ScriptOutput(flow: ScriptFlow(next: 'A')));
      final a = add(t, 'A', scripts: const Scripts(post: 'x'));
      final r = await t.c
          .read(runnerProvider.notifier)
          .run(RunConfig(name: 'X', requestIds: [a], maxSteps: 50));
      expect(r.entries.length, 50);
      expect(r.stoppedEarly, isTrue);
    });

    test('requestsUnder walks folders in tree order', () {
      final t = setup();
      final f = t.s.repo.createFolder(t.col, 'F');
      final a = add(t, 'A');
      final b = t.s.repo.createRequest(
        f,
        const HttpRequestItem(id: '', name: 'B', url: 'http://x.test'),
      );
      final ids = requestsUnder(t.s.repo, t.col).map((n) => n.id).toList();
      expect(ids.toSet(), {a, b});
      expect(ids.length, 2);
    });
  });
}
