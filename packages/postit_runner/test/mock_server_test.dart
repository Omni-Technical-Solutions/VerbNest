import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:postit_core/postit_core.dart';
import 'package:postit_runner/postit_runner.dart';
import 'package:postit_storage/postit_storage.dart';
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
  }) async {
    final c = HttpClient();
    final req = await c.openUrl(
      method,
      Uri.parse('http://127.0.0.1:${mock!.port}$path'),
    );
    headers.forEach(req.headers.set);
    final res = await req.close();
    final body = await utf8.decodeStream(res);
    c.close();
    return (res.statusCode, body, res.headers);
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
        headers: {'X-PostIt-Example': 'gone'},
      );
      expect(r.$1, 410);

      expect((await call('POST', '/v1/users')).$1, 201);
      final miss = await call('DELETE', '/v1/users');
      expect(miss.$1, 404);
      expect(miss.$2, contains('GET /v1/users/*'));
      expect(miss.$2, isNot(contains('none')));
    },
  );
}
