import 'dart:convert';

import 'package:verbnest_http/verbnest_http.dart';
import 'package:test/test.dart';
import 'package:test_server/h2_server.dart';
import 'package:test_server/test_server.dart';

void main() {
  late bool available;
  late H2TestServer server;
  final engine = HttpEngine();

  setUpAll(() async {
    available = await TestServer.tlsAvailable;
    if (available) server = await H2TestServer.start();
  });
  tearDownAll(() async {
    if (available) await server.close();
  });

  HttpRequestSpec req(
    String path, {
    String method = 'GET',
    List<Header> headers = const [],
    List<int>? body,
    HttpVersionPref version = HttpVersionPref.auto,
  }) => HttpRequestSpec(
    method: method,
    url: Uri.parse('${server.baseUrl}$path'),
    headers: headers,
    body: body,
    settings: HttpSettings(verifyTls: false, httpVersion: version),
  );

  Map<String, dynamic> echoed(HttpResponseRecord r) =>
      jsonDecode(r.bodyText) as Map<String, dynamic>;

  void h2Test(String name, Future<void> Function() body) =>
      test(name, () async {
        if (!available) markTestSkipped('openssl is not available');
        await body();
      });

  group('HTTP/2', () {
    h2Test('auto negotiates h2 through ALPN', () async {
      final r = await engine.send(req('/echo?a=1'));
      expect(r.status, 200);
      expect(r.httpVersion, '2');
      expect(r.tls?.protocol, 'h2');
      expect(echoed(r)['method'], 'GET');
      expect(echoed(r)['query'], 'a=1');
    });

    h2Test('sends lower-case fields without connection headers', () async {
      final r = await engine.send(
        req(
          '/echo',
          headers: [('X-Custom', 'v'), ('Connection', 'keep-alive')],
        ),
      );
      final names = [for (final h in echoed(r)['headers'] as List) h[0]];
      expect(names, contains('x-custom'));
      expect(names, isNot(contains('connection')));
      expect(names, isNot(contains('host')));
      expect(echoed(r)['authority'], '127.0.0.1:${server.port}');
      expect(r.sent.head, startsWith('GET /echo HTTP/2'));
      expect(r.sent.head, contains(':authority: 127.0.0.1'));
    });

    h2Test('posts a body and sets content-length', () async {
      final r = await engine.send(
        req('/echo', method: 'POST', body: utf8.encode('{"a":1}')),
      );
      expect(utf8.decode(base64Decode(echoed(r)['bodyBase64'])), '{"a":1}');
      final names = [for (final h in echoed(r)['headers'] as List) h[0]];
      expect(names, contains('content-length'));
    });

    h2Test('decodes gzip and keeps the wire size', () async {
      final r = await engine.send(req('/gzip'));
      expect(r.bodyText, 'gzipped body');
      expect(r.wireBodySize, isNot(r.body.length));
    });

    h2Test('returns non-200 statuses', () async {
      final r = await engine.send(req('/status/404'));
      expect(r.status, 404);
      expect(r.reason, isEmpty);
    });

    h2Test('ignores trailers', () async {
      final r = await engine.send(req('/trailers'));
      expect(r.bodyText, 'with trailers');
      expect(r.header('x-trailer'), isNull);
    });

    h2Test('reads a large body', () async {
      final r = await engine.send(req('/large/3'));
      expect(r.body.length, 3 * 1024 * 1024);
    });

    h2Test('reports timings', () async {
      final r = await engine.send(req('/echo'));
      expect(r.timings.tls, greaterThan(Duration.zero));
      expect(r.timings.total, greaterThan(Duration.zero));
    });

    h2Test('http1 only fails clearly against an h2-only server', () async {
      expect(
        engine.send(req('/echo', version: HttpVersionPref.http1)),
        throwsA(isA<HttpEngineError>()),
      );
    });

    h2Test('cancel aborts an h2 request', () async {
      final token = CancelToken();
      final f = engine.send(req('/large/50'), cancel: token);
      token.cancel();
      await expectLater(f, throwsA(isA<CancelledError>()));
    });
  });

  test('HTTP/2 needs https', () async {
    expect(
      engine.send(
        HttpRequestSpec(
          method: 'GET',
          url: Uri.parse('http://127.0.0.1:1/'),
          settings: const HttpSettings(httpVersion: HttpVersionPref.http2),
        ),
      ),
      throwsA(isA<ProtocolError>()),
    );
  });

  test('version codes round trip', () {
    for (final v in HttpVersionPref.values) {
      expect(HttpVersionPref.fromCode(v.code), v);
    }
    expect(HttpVersionPref.fromCode(null), HttpVersionPref.auto);
  });
}
