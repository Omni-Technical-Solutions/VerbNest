import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:postit_app/src/scripting/script_engine.dart';
import 'package:postit_app/src/scripting/script_io.dart';

ScriptInput input(
  String code, {
  ScriptPhase phase = ScriptPhase.post,
  Map<ScriptScope, Map<String, String>> vars = const {},
  bool withResponse = true,
  Map<String, String> data = const {},
}) => ScriptInput(
  data: data,
  code: code,
  phase: phase,
  requestName: 'R',
  requestId: 'id1',
  request: {
    'method': 'GET',
    'url': 'https://api.test/a?x=1',
    'headers': [
      {'key': 'Accept', 'value': '*/*'},
    ],
    'body': '',
  },
  response: withResponse
      ? {
          'code': 201,
          'status': 'Created',
          'headers': [
            {'key': 'Content-Type', 'value': 'application/json'},
          ],
          'body': '{"id":7,"tags":["a","b"],"name":"x"}',
          'time': 12,
          'size': 36,
        }
      : null,
  variables: vars,
  environmentName: 'dev',
);

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  final engine = FjsScriptEngine();

  Future<ScriptOutput> run(
    String code, {
    ScriptPhase phase = ScriptPhase.post,
    Map<ScriptScope, Map<String, String>> vars = const {},
    Duration timeout = defaultScriptTimeout,
  }) => engine.run(
    input(
      code,
      phase: phase,
      vars: vars,
      withResponse: phase == ScriptPhase.post,
    ),
    timeout: timeout,
  );

  testWidgets('iteration data and run flow control', (tester) async {
    final o = await engine.run(
      input(
        '''
        pm.test('data', function () {
          pm.expect(pm.iterationData.get('user')).to.equal('ann');
          pm.expect(pm.variables.get('user')).to.equal('ann');
        });
        pm.execution.setNextRequest('Other');
        ''',
        data: {'user': 'ann'},
      ),
    );
    expect(o.error, isNull);
    expect(o.tests.single.passed, isTrue);
    expect(o.flow.next, 'Other');

    final stop = await engine.run(input('pm.execution.setNextRequest(null)'));
    expect(stop.flow.stop, isTrue);

    final skip = await engine.run(
      input(
        'pm.execution.skipRequest()',
        phase: ScriptPhase.pre,
        withResponse: false,
      ),
    );
    expect(skip.flow.skip, isTrue);

    final badSkip = await engine.run(input('pm.execution.skipRequest()'));
    expect(badSkip.error, contains('pre-request'));
  });

  testWidgets('tests, expect and response helpers', (tester) async {
    final o = await run('''
      pm.test('status', function () { pm.response.to.have.status(201); });
      pm.test('json', function () {
        const j = pm.response.json();
        pm.expect(j.id).to.equal(7);
        pm.expect(j.tags).to.have.lengthOf(2).and.include('a');
        pm.expect(j).to.have.property('name', 'x');
        pm.expect(j).to.deep.equal({id: 7, tags: ['a', 'b'], name: 'x'});
        pm.expect(pm.response.responseTime).to.be.below(100);
        pm.expect('abc').to.be.a('string').and.not.be.empty;
      });
      pm.test('header', function () {
        pm.expect(pm.response.headers.get('content-type')).to.include('json');
      });
      pm.test('wrong', function () { pm.expect(1).to.equal(2); });
      pm.test.skip('later');
    ''');
    expect(o.error, isNull);
    expect(o.tests.map((t) => t.status), [
      'pass',
      'pass',
      'pass',
      'fail',
      'skip',
    ]);
    expect(o.tests[3].message, contains('expected 1 to equal 2'));
  });

  testWidgets('variables per scope and changes are reported', (tester) async {
    final o = await run(
      '''
      pm.environment.set('token', 'abc');
      pm.collectionVariables.set('n', 5);
      pm.globals.unset('old');
      pm.variables.set('tmp', {a: 1});
      console.log('host', pm.variables.get('host'), pm.environment.name);
      pm.test('replace', function () {
        pm.expect(pm.variables.replaceIn('{{host}}/x')).to.equal('h.test/x');
      });
    ''',
      vars: {
        ScriptScope.environment: {'host': 'h.test'},
        ScriptScope.globals: {'old': '1'},
      },
    );
    expect(o.error, isNull);
    String? change(ScriptScope s, String k) =>
        o.changes[s]!.firstWhere((c) => c.key == k).value;
    expect(change(ScriptScope.environment, 'token'), 'abc');
    expect(change(ScriptScope.collection, 'n'), '5');
    expect(change(ScriptScope.globals, 'old'), isNull);
    expect(change(ScriptScope.local, 'tmp'), '{"a":1}');
    expect(o.logs.single.text, 'host h.test dev');
    expect(o.tests.single.status, 'pass');
  });

  testWidgets('pre-request scripts can change the request', (tester) async {
    final o = await run('''
      pm.request.headers.upsert({key: 'accept', value: 'application/json'});
      pm.request.headers.add({key: 'X-A', value: '1'});
      pm.request.method = 'POST';
      pm.request.url = pm.request.url.toString() + '&y=2';
      pm.request.body.raw = '{"a":1}';
    ''', phase: ScriptPhase.pre);
    expect(o.error, isNull);
    final r = o.request!;
    expect(r['method'], 'POST');
    expect(r['url'], 'https://api.test/a?x=1&y=2');
    expect(r['body'], '{"a":1}');
    final headers = (r['headers'] as List).cast<Map>();
    expect(headers.map((h) => h['key']), ['Accept', 'X-A']);
    expect(headers.first['value'], 'application/json');
  });

  testWidgets('unsupported APIs and errors are reported by name', (
    tester,
  ) async {
    var o = await run('pm.cookies.jar()');
    expect(o.error, contains('pm.cookies.jar is not supported'));
    o = await run('require("fs")');
    expect(o.error, contains("require('fs') is not supported"));
    o = await run('pm.response.json(', phase: ScriptPhase.post);
    expect(o.error, contains('SyntaxError'));
    o = await run('null.x', phase: ScriptPhase.post);
    expect(o.error, contains('TypeError'));
    o = await run('pm.response.code', phase: ScriptPhase.pre);
    expect(o.error, contains('only available in post-response'));
  });

  testWidgets('the sandbox has no files, sockets or host globals', (
    tester,
  ) async {
    final o = await run('''
      pm.test('no host access', function () {
        pm.expect(typeof process).to.equal('undefined');
        pm.expect(typeof fetch).to.equal('undefined');
        pm.expect(typeof XMLHttpRequest).to.equal('undefined');
        pm.expect(typeof fs).to.equal('undefined');
        pm.expect(typeof setTimeout).to.equal('undefined');
      });
    ''');
    expect(o.error, isNull);
    expect(o.tests.single.status, 'pass', reason: o.tests.single.message);
  });

  testWidgets('an infinite loop times out and the engine stays usable', (
    tester,
  ) async {
    final started = DateTime.now();
    final o = await run('while (true) {}', timeout: const Duration(seconds: 1));
    expect(o.error, contains('timed out'));
    expect(
      DateTime.now().difference(started),
      lessThan(const Duration(seconds: 4)),
    );
    final again = await run('pm.test("ok", function () {});');
    expect(again.tests.single.passed, isTrue);
  });

  testWidgets('a script that eats memory is stopped', (tester) async {
    final o = await run(
      'var a = []; while (true) { a.push(new Array(100000).fill("x".repeat(100))); }',
      timeout: const Duration(seconds: 20),
    );
    expect(o.error, isNotNull);
    expect(o.error, isNot(contains('timed out')));
  });

  testWidgets('start-up cost of a trivial script', (tester) async {
    await run('1'); // loads the native library once
    final times = <int>[];
    for (var i = 0; i < 10; i++) {
      final o = await run('pm.test("t", function () {});');
      times.add(o.elapsed.inMilliseconds);
    }
    times.sort();
    // ignore: avoid_print
    print('SCRIPT median ${times[5]} ms, max ${times.last} ms');
    expect(times[5], lessThan(500));
  });
}
