import 'dart:convert';
import 'dart:io';

import 'package:verbnest_core/verbnest_core.dart';
import 'package:verbnest_http/verbnest_http.dart';
import 'package:test/test.dart';

const _gql = GraphqlBody(query: '{ me { id } }', persisted: true);

Future<PreparedRequest> _build(String method, String url) =>
    RequestBuilder().build(
      HttpRequestItem(id: 'i', name: 'n', method: method, url: url, body: _gql),
      VariableResolver(VariableScopes()),
    );

void main() {
  test('the hash is the SHA-256 of the query text', () {
    expect(
      persistedQueryHash('{ __typename }'),
      '7f56e67dd21ab3f30d1ff8b7bed08893f0a0db86449836189b361dd1e56ddb4b',
    );
  });

  test('a persisted POST sends only the hash first', () async {
    final p = await _build('POST', 'http://h.test/graphql');
    final sent = jsonDecode(utf8.decode(p.spec.body!)) as Map;
    expect(sent.containsKey('query'), isFalse);
    expect(sent['extensions']['persistedQuery']['version'], 1);
    final full = jsonDecode(utf8.decode(p.persistedFallback!.body!)) as Map;
    expect(full['query'], '{ me { id } }');
    expect(
      full['extensions']['persistedQuery']['sha256Hash'],
      sent['extensions']['persistedQuery']['sha256Hash'],
    );
  });

  test('a persisted GET carries the hash in the URL', () async {
    final p = await _build('GET', 'http://h.test/graphql');
    expect(p.spec.url.queryParameters.containsKey('query'), isFalse);
    expect(p.spec.url.queryParameters['extensions'], contains('sha256Hash'));
    expect(p.persistedFallback!.url.queryParameters['query'], '{ me { id } }');
  });

  test('a normal query has no fallback', () async {
    final p = await RequestBuilder().build(
      HttpRequestItem(
        id: 'i',
        name: 'n',
        method: 'POST',
        url: 'http://h.test/g',
        body: const GraphqlBody(query: '{ a }'),
      ),
      VariableResolver(VariableScopes()),
    );
    expect(p.persistedFallback, isNull);
  });

  test('PersistedQueryNotFound triggers one retry with the query', () async {
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    addTearDown(() => server.close(force: true));
    final seen = <Map<dynamic, dynamic>>[];
    server.listen((req) async {
      final m = jsonDecode(await utf8.decoder.bind(req).join()) as Map;
      seen.add(m);
      req.response.write(
        m.containsKey('query')
            ? '{"data":{"me":{"id":"1"}}}'
            : '{"errors":[{"message":"PersistedQueryNotFound"}]}',
      );
      await req.response.close();
    });
    final p = await _build('POST', 'http://127.0.0.1:${server.port}/graphql');
    final r = await sendPrepared(HttpEngine(), p);
    expect(r.bodyText, contains('"id":"1"'));
    expect(seen.length, 2);
    expect(seen[0].containsKey('query'), isFalse);
    expect(seen[1]['query'], '{ me { id } }');
  });

  test('a known hash is answered without a retry', () async {
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    addTearDown(() => server.close(force: true));
    var hits = 0;
    server.listen((req) async {
      hits++;
      await utf8.decoder.bind(req).join();
      req.response.write('{"data":{}}');
      await req.response.close();
    });
    final p = await _build('POST', 'http://127.0.0.1:${server.port}/graphql');
    await sendPrepared(HttpEngine(), p);
    expect(hits, 1);
  });

  test('persisted survives JSON', () {
    final back = RequestBody.fromJson(_gql.toJson()) as GraphqlBody;
    expect(back.persisted, isTrue);
    expect(const GraphqlBody().toJson()['graphql'], isEmpty);
  });
}
