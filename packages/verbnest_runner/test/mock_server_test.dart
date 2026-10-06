import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:verbnest_core/verbnest_core.dart';
import 'package:verbnest_runner/verbnest_runner.dart';
import 'package:verbnest_storage/verbnest_storage.dart';
import 'package:test/test.dart';

void main() {
  late WorkspaceRepository repo;
  late String col;
  MockServer? mock;

  setUp(() {
    repo = WorkspaceRepository(WorkspaceDatabase.memory());
    col = repo.createCollection('API');
    repo.saveVariables(VariableOwner.collection(col), [
      const Variable(key: 'base', value: 'https://api.example.com/v1'),
    ]);
  });
  tearDown(() => mock?.close());

  void example(String reqId, String name, int status, String body) =>
      repo.addExample(reqId, name, {
        'status': status,
        'reason': 'x',
        'headers': [
          ['Content-Type', 'application/json'],
          ['Content-Length', '999'],
          ['X-Custom', 'yes'],
        ],
      }, Uint8List.fromList(utf8.encode(body)));

  Future<(int, String, HttpHeaders)> call(
    String method,
    String path, {
    Map<String, String> headers = const {},
    String? body,
  }) async {
    final c = HttpClient();
    final req = await c.openUrl(
      method,
      Uri.parse('http://127.0.0.1:${mock!.port}$path'),
    );
    headers.forEach(req.headers.set);
    if (body != null) req.write(body);
    final res = await req.close();
    final text = await utf8.decodeStream(res);
    c.close();
    return (res.statusCode, text, res.headers);
  }

  test(
    'serves examples by method and path with variables and params',
    () async {
      final a = repo.createRequest(
        col,
        HttpRequestItem(id: '', name: 'user', url: '{{base}}/users/:id?x=1'),
      );
      example(a, 'ok', 200, '{"id":1}');
      example(a, 'gone', 410, '{"error":"gone"}');
      final b = repo.createRequest(
        col,
        HttpRequestItem(
          id: '',
          name: 'create',
          method: 'POST',
          url: '{{base}}/users',
        ),
      );
      example(b, 'made', 201, '{}');
      repo.createRequest(
        col,
        HttpRequestItem(id: '', name: 'bare', url: '{{base}}/none'),
      );

      mock = await MockServer.start(MockServer.routesFor(repo, col));

      var r = await call('GET', '/v1/users/42');
      expect((r.$1, r.$2), (200, '{"id":1}'));
      expect(r.$3.value('x-custom'), 'yes');
      expect(r.$3.contentLength, 8);

      r = await call(
        'GET',
        '/v1/users/42',
        headers: {'X-Verbnest-Example': 'gone'},
      );
      expect(r.$1, 410);

      expect((await call('POST', '/v1/users')).$1, 201);
      final miss = await call('DELETE', '/v1/users');
      expect(miss.$1, 404);
      expect(miss.$2, contains('GET /v1/users/*'));
      expect(miss.$2, isNot(contains('none')));
    },
  );

  test('query and body pin a route; the most specific one wins', () async {
    final loose = repo.createRequest(
      col,
      HttpRequestItem(id: '', name: 'list', url: '{{base}}/items'),
    );
    example(loose, 'all', 200, '"all"');
    final paged = repo.createRequest(
      col,
      HttpRequestItem(id: '', name: 'page', url: '{{base}}/items?page=2'),
    );
    example(paged, 'page2', 200, '"page2"');
    final any = repo.createRequest(
      col,
      HttpRequestItem(id: '', name: 'filter', url: '{{base}}/items?q='),
    );
    example(any, 'search', 200, '"search"');
    final post = repo.createRequest(
      col,
      HttpRequestItem(
        id: '',
        name: 'login',
        method: 'POST',
        url: '{{base}}/login',
        body: const RawBody(RawBodyLanguage.json, '{"user": "ann"}'),
      ),
    );
    example(post, 'ann', 200, '"hi ann"');
    final other = repo.createRequest(
      col,
      HttpRequestItem(
        id: '',
        name: 'login any',
        method: 'POST',
        url: '{{base}}/login',
      ),
    );
    example(other, 'denied', 401, '"no"');

    mock = await MockServer.start(MockServer.routesFor(repo, col));

    expect((await call('GET', '/v1/items')).$2, '"all"');
    expect((await call('GET', '/v1/items?page=2')).$2, '"page2"');
    expect((await call('GET', '/v1/items?page=3')).$2, '"all"');
    expect((await call('GET', '/v1/items?q=cat')).$2, '"search"');

    var r = await call('POST', '/v1/login', body: '{"user":"ann"}');
    expect((r.$1, r.$2), (200, '"hi ann"'));
    r = await call('POST', '/v1/login', body: '{"user":"bob"}');
    expect((r.$1, r.$2), (401, '"no"'));
  });

  test('delay applies by default and per request, capped', () async {
    final a = repo.createRequest(
      col,
      HttpRequestItem(id: '', name: 'slow', url: '{{base}}/slow'),
    );
    example(a, 'ok', 200, '{}');
    mock = await MockServer.start(
      MockServer.routesFor(repo, col),
      delay: const Duration(milliseconds: 150),
    );

    var sw = Stopwatch()..start();
    await call('GET', '/v1/slow');
    expect(sw.elapsedMilliseconds, greaterThanOrEqualTo(140));

    sw = Stopwatch()..start();
    await call('GET', '/v1/slow', headers: {'X-Verbnest-Delay': '0'});
    expect(sw.elapsedMilliseconds, lessThan(120));
  });

  test('the pre-rename X-PostIt headers still work', () async {
    final db = WorkspaceDatabase.memory();
    final repo = WorkspaceRepository(db);
    final col = repo.createCollection('API');
    final id = repo.createRequest(
      col,
      HttpRequestItem(id: '', name: 'u', url: '{{base}}/old'),
    );
    expect(id, isNotNull);
    final mock = await MockServer.start(MockServer.routesFor(repo, col));
    addTearDown(mock.close);
    final c = HttpClient();
    addTearDown(c.close);
    final req = await c.getUrl(Uri.parse('http://127.0.0.1:${mock.port}/old'));
    req.headers.set('X-PostIt-Delay', '0');
    req.headers.set('X-PostIt-Example', 'none');
    final res = await req.close();
    await res.drain<void>();
    expect(res.statusCode, isNot(500));
  });
}
