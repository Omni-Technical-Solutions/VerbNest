import 'package:postit_core/postit_core.dart';
import 'package:postit_http/postit_http.dart';
import 'package:postit_script/postit_script.dart';
import 'package:postit_runner/postit_runner.dart';
import 'package:postit_storage/postit_storage.dart';
import 'package:test/test.dart';
import 'package:test_server/test_server.dart';

void main() {
  late TestServer server;
  late WorkspaceRepository repo;
  late String col;

  setUp(() async {
    server = await TestServer.start();
    repo = WorkspaceRepository(WorkspaceDatabase.memory());
    col = repo.createCollection('API');
    repo.saveVariables(VariableOwner.collection(col), [
      Variable(key: 'base', value: server.baseUrl),
      const Variable(key: 'token', value: '', secret: true),
    ]);
  });

  String add(String name, HttpRequestItem Function(HttpRequestItem) f) =>
      repo.createRequest(col, f(HttpRequestItem(id: '', name: name)));

  test('runs requests with variables, overrides and assertions', () async {
    final a = add(
      'ok',
      (i) => i.copyWith(
        url: '{{base}}/echo?t={{token}}',
        assertions: [
          const Assertion(target: AssertionTarget.status, value: '200'),
        ],
      ),
    );
    final b = add(
      'wrong',
      (i) => i.copyWith(
        url: '{{base}}/status/404',
        assertions: [
          const Assertion(target: AssertionTarget.status, value: '200'),
        ],
      ),
    );
    final sender = HeadlessSender(
      repo: repo,
      engine: HttpEngine(),
      overrides: {'token': 'abc'},
    );
    final report = await executeRun(
      config: RunConfig(name: 'API', requestIds: [a, b]),
      repo: repo,
      step: sender.step,
    );
    expect(report.entries.map((e) => e.status), [200, 404]);
    expect(report.entries.first.ok, isTrue);
    expect(report.entries.last.failedTests, 1);
    expect(report.ok, isFalse);
    expect(server.requests.first.target, contains('t=abc'));
  });

  test(
    'a connection failure becomes an entry error, not an exception',
    () async {
      final a = add('down', (i) => i.copyWith(url: 'http://127.0.0.1:1/'));
      final sender = HeadlessSender(repo: repo, engine: HttpEngine());
      final report = await executeRun(
        config: RunConfig(name: 'x', requestIds: [a]),
        repo: repo,
        step: sender.step,
      );
      expect(report.entries.single.error, isNotNull);
    },
  );

  test('notes requests whose scripts cannot run', () async {
    final a = add(
      'scripted',
      (i) => i.copyWith(
        url: '{{base}}/echo',
        scripts: const Scripts(post: 'pm.test("x", () => {})'),
      ),
    );
    final sender = HeadlessSender(repo: repo, engine: HttpEngine());
    await executeRun(
      config: RunConfig(name: 'x', requestIds: [a]),
      repo: repo,
      step: sender.step,
    );
    expect(sender.scriptsSkipped, {'scripted'});
  });

  test('stopOnFailure and iterations come from executeRun', () async {
    final a = add('bad', (i) => i.copyWith(url: 'http://127.0.0.1:1/'));
    final b = add('later', (i) => i.copyWith(url: '{{base}}/echo'));
    final sender = HeadlessSender(repo: repo, engine: HttpEngine());
    final report = await executeRun(
      config: RunConfig(name: 'x', requestIds: [a, b], stopOnFailure: true),
      repo: repo,
      step: sender.step,
    );
    expect(report.entries, hasLength(1));
    expect(report.stoppedEarly, isTrue);
  });

  test('websocket requests are skipped, not failed', () async {
    final a = add('live', (i) => i.copyWith(url: 'ws://127.0.0.1:1/socket'));
    final sender = HeadlessSender(repo: repo, engine: HttpEngine());
    final report = await executeRun(
      config: RunConfig(name: 'x', requestIds: [a]),
      repo: repo,
      step: sender.step,
    );
    expect(report.entries.single.skipped, isTrue);
    expect(report.ok, isTrue);
  });

  group('scripts', () {
    late bool hasRuntime;
    setUpAll(() async => hasRuntime = await ProcessScriptEngine.available());

    test('a post-response script feeds the next request', () async {
      if (!hasRuntime) return;
      final a = add(
        'login',
        (i) => i.copyWith(
          url: '{{base}}/echo',
          scripts: const Scripts(
            post:
                'pm.collectionVariables.set("who", "from-script");'
                'pm.test("ran", () => pm.expect(pm.response.code).to.equal(200));',
          ),
        ),
      );
      final b = add('use', (i) => i.copyWith(url: '{{base}}/echo?w={{who}}'));
      final sender = HeadlessSender(
        repo: repo,
        engine: HttpEngine(),
        scripts: ProcessScriptEngine(),
      );
      final report = await executeRun(
        config: RunConfig(name: 'x', requestIds: [a, b]),
        repo: repo,
        step: sender.step,
      );
      expect(report.entries.first.tests.single.passed, isTrue);
      expect(server.requests.last.target, contains('w=from-script'));
      expect(sender.scriptsSkipped, isEmpty);
    });

    test('a pre-request script can skip; a failing one is an error', () async {
      if (!hasRuntime) return;
      final a = add(
        'skipme',
        (i) => i.copyWith(
          url: '{{base}}/echo',
          scripts: const Scripts(pre: 'pm.execution.skipRequest();'),
        ),
      );
      final b = add(
        'broken',
        (i) => i.copyWith(
          url: '{{base}}/echo',
          scripts: const Scripts(pre: 'throw new Error("nope")'),
        ),
      );
      final sender = HeadlessSender(
        repo: repo,
        engine: HttpEngine(),
        scripts: ProcessScriptEngine(),
      );
      final report = await executeRun(
        config: RunConfig(name: 'x', requestIds: [a, b]),
        repo: repo,
        step: sender.step,
      );
      expect(report.entries.first.skipped, isTrue);
      expect(report.entries.last.error, contains('nope'));
      expect(server.requests, isEmpty);
    });
  });
}
