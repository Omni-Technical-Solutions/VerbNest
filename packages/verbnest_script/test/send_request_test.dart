import 'package:verbnest_http/verbnest_http.dart';
import 'package:verbnest_core/verbnest_core.dart';
import 'package:verbnest_script/verbnest_script.dart';
import 'package:verbnest_storage/verbnest_storage.dart';
import 'package:test/test.dart';

class _Vars implements ScriptVariables {
  @override
  Map<ScriptScope, Map<String, String>> values(
    String requestId,
    String? envId,
    Map<String, String> local,
  ) => {for (final s in ScriptScope.values) s: <String, String>{}};

  @override
  void apply(
    String requestId,
    String? envId,
    Map<ScriptScope, List<VariableChange>> changes,
    Map<String, String> local,
    List<ConsoleLine> logs,
  ) {}
}

class _Host implements ScriptHost {
  _Host({this.fail = false});

  final bool fail;
  final sent = <Map<String, Object?>>[];

  @override
  Future<Map<String, Object?>> send(Map<String, Object?> request) async {
    sent.add(request);
    if (fail) throw const FormatException('unreachable');
    return {
      'code': 200,
      'status': 'OK',
      'headers': [
        {'key': 'X-N', 'value': '${sent.length}'},
      ],
      'body': '{"n":${sent.length}}',
      'time': 1,
      'size': 8,
    };
  }

  @override
  Map<String, String> cookiesFor(String url) => {'sid': 'abc'};
}

void main() async {
  blockedHostTests();
  final hasNode = await ProcessScriptEngine.available();
  final skip = hasNode ? null : 'node is not installed';
  final engine = ProcessScriptEngine();

  Future<ScriptPhaseResult> run(String post, ScriptHost? host) {
    final repo = WorkspaceRepository(WorkspaceDatabase.memory());
    final col = repo.createCollection('C');
    final item = HttpRequestItem(
      id: '',
      name: 'r',
      url: 'http://x.test/',
      scripts: Scripts(post: post),
    );
    final id = repo.createRequest(col, item);
    return runScriptPhaseWith(
      repo: repo,
      variables: _Vars(),
      engine: engine,
      requestId: id,
      item: repo.getRequest(id),
      envId: null,
      phase: ScriptPhase.post,
      request: requestToMap(item),
      response: const {
        'code': 200,
        'status': 'OK',
        'headers': <Object?>[],
        'body': '',
        'time': 1,
        'size': 0,
      },
      host: host,
    );
  }

  test('a callback gets the response and each request is sent once', () async {
    final host = _Host();
    final r = await run('''
pm.sendRequest({url: 'http://a.test/x', method: 'POST', header: {'X-A': '1'}, body: {mode: 'raw', raw: 'hi'}}, (err, res) => {
  pm.test('first', () => pm.expect(res.json().n).to.equal(1));
  pm.sendRequest('http://b.test/', (e2, r2) => {
    pm.test('second', () => pm.expect(r2.headers.get('x-n')).to.equal('2'));
  });
});
console.log('after');
''', host);
    expect(r.error, isNull);
    expect(r.tests.map((t) => '${t.name}:${t.status}'), [
      'first:pass',
      'second:pass',
    ]);
    expect(r.logs.map((l) => l.text), ['after']);
    expect(host.sent.length, 2);
    expect(host.sent.first['method'], 'POST');
    expect(host.sent.first['body'], 'hi');
    expect((host.sent.first['headers'] as List).single, {
      'key': 'X-A',
      'value': '1',
    });
  }, skip: skip);

  test('a failed request reaches the callback as an error', () async {
    final r = await run('''
pm.sendRequest('http://down.test/', (err) => {
  pm.test('err', () => pm.expect(err.message).to.equal('unreachable'));
});
''', _Host(fail: true));
    expect(r.error, isNull);
    expect(r.tests.single.status, 'pass');
  }, skip: skip);

  test('without a host the callback gets an error', () async {
    final r = await run('''
pm.sendRequest('http://x.test/', (err) => pm.test('e', () => pm.expect(err.message).to.include('not available')));
''', null);
    expect(r.tests.single.status, 'pass');
  }, skip: skip);

  test('a script that swallows the wait is still answered', () async {
    final host = _Host();
    final r = await run('''
try { pm.sendRequest('http://x.test/', (e, res) => pm.test('got', () => pm.expect(res.code).to.equal(200))); } catch (e) {}
''', host);
    expect(r.error, isNull);
    expect(r.tests.single.name, 'got');
    expect(host.sent.length, 1);
  }, skip: skip);

  test('pm.cookies reads the host cookies', () async {
    final r = await run('''
pm.test('cookie', () => {
  pm.expect(pm.cookies.get('sid')).to.equal('abc');
  pm.expect(pm.cookies.has('nope')).to.equal(false);
  pm.expect(pm.cookies.toObject()).to.eql({sid: 'abc'});
});
''', _Host());
    expect(r.tests.single.status, 'pass');
  }, skip: skip);

  test('too many requests stop the script with an error', () async {
    final host = _Host();
    final r = await run('''
for (let i = 0; i < 50; i++) pm.sendRequest('http://x.test/' + i, () => {});
''', host);
    expect(r.error, contains('at most $maxScriptRequests'));
    expect(host.sent.length, maxScriptRequests);
  }, skip: skip);
}

void blockedHostTests() {
  group('EngineScriptHost blocked hosts', () {
    for (final url in [
      'http://169.254.169.254/latest/meta-data',
      'http://[fe80::1]/x',
      'http://metadata.google.internal/x',
      'http://[::ffff:169.254.169.254]/x',
    ]) {
      test(url, () {
        final host = EngineScriptHost(HttpEngine());
        expect(
          host.send({'url': url, 'method': 'GET'}),
          throwsA(isA<FormatException>()),
        );
      });
    }
  });
}
