import 'dart:convert';

import 'package:verbnest_http/verbnest_http.dart';
import 'package:test/test.dart';
import 'package:test_server/test_server.dart';

void main() {
  tlsTests();
  late TestServer server;
  final engine = HttpEngine();

  setUp(() async => server = await TestServer.start());
  tearDown(() => server.close());

  HttpRequestSpec req(
    String path, {
    String method = 'GET',
    List<Header> headers = const [],
    List<int>? body,
    HttpSettings settings = const HttpSettings(),
  }) => HttpRequestSpec(
    method: method,
    url: Uri.parse('${server.baseUrl}$path'),
    headers: headers,
    body: body,
    settings: settings,
  );

  Map<String, dynamic> echoed(HttpResponseRecord r) =>
      jsonDecode(r.bodyText) as Map<String, dynamic>;

  group('wire fidelity', () {
    test('preserves header order and casing', () async {
      final r = await engine.send(
        req(
          '/echo',
          headers: [('X-Zebra', '1'), ('x-apple', '2'), ('X-MiXeD-Case', '3')],
        ),
      );
      final names = (echoed(r)['headers'] as List).map((h) => h[0]).toList();
      expect(names.take(3), ['X-Zebra', 'x-apple', 'X-MiXeD-Case']);
    });

    test('adds auto headers but lets the user override them', () async {
      final auto = await engine.send(req('/echo'));
      final autoNames = (echoed(auto)['headers'] as List).map(
        (h) => (h[0] as String).toLowerCase(),
      );
      expect(autoNames, containsAll(['host', 'user-agent', 'accept']));

      final custom = await engine.send(
        req('/echo', headers: [('user-agent', 'mine/1')]),
      );
      final ua = (echoed(custom)['headers'] as List).where(
        (h) => (h[0] as String).toLowerCase() == 'user-agent',
      );
      expect(ua.map((h) => h[1]), ['mine/1']);
    });

    test('supports custom methods and exposes the sent request', () async {
      final r = await engine.send(req('/echo', method: 'PURGE'));
      expect(echoed(r)['method'], 'PURGE');
      expect(r.sent.head, startsWith('PURGE /echo HTTP/1.1\r\n'));
    });

    test('sends body bytes unchanged with Content-Length', () async {
      final bytes = [0, 255, 10, 13, 128];
      final r = await engine.send(req('/echo', method: 'POST', body: bytes));
      expect(base64Decode(echoed(r)['bodyBase64'] as String), bytes);
      expect(r.sent.head, contains('Content-Length: 5'));
    });

    test('keeps the raw query string', () async {
      final r = await engine.send(req('/echo?a=1&a=2&b=%20x'));
      expect(echoed(r)['query'], 'a=1&a=2&b=%20x');
    });
  });

  group('responses', () {
    test('status, reason and timings', () async {
      final r = await engine.send(req('/status/404'));
      expect(r.status, 404);
      expect(r.reason, 'Not Found');
      expect(r.timings.total, greaterThan(Duration.zero));
    });

    test('decodes gzip and reports wire size', () async {
      final r = await engine.send(req('/gzip'));
      expect(r.bodyText, 'gzipped body');
      expect(r.wireBodySize, isNot(r.body.length));
      expect(r.header('content-encoding'), 'gzip');
    });

    test('leaves gzip untouched when auto-decompress is off', () async {
      final r = await engine.send(
        req('/gzip', settings: const HttpSettings(autoDecompress: false)),
      );
      expect(r.bodyText, isNot('gzipped body'));
    });

    test('reads chunked bodies', () async {
      final r = await engine.send(req('/chunked'));
      expect(r.bodyText, 'hello chunked world');
    });

    test('reads a large body', () async {
      final r = await engine.send(req('/large/2'));
      expect(r.body.length, 2 * 1024 * 1024);
    });
  });

  group('redirects', () {
    test('follows and records hops', () async {
      final r = await engine.send(req('/redirect/3'));
      expect(r.status, 200);
      expect(r.redirects, hasLength(3));
      expect(r.finalUrl.path, '/echo');
    });

    test('does not follow when disabled', () async {
      final r = await engine.send(
        req(
          '/redirect/1',
          settings: const HttpSettings(followRedirects: false),
        ),
      );
      expect(r.status, 302);
      expect(r.header('location'), '/echo');
    });

    test('enforces the max redirect count', () async {
      expect(
        engine.send(
          req('/redirect/5', settings: const HttpSettings(maxRedirects: 2)),
        ),
        throwsA(isA<TooManyRedirectsError>()),
      );
    });

    test(
      'credential-like headers do not follow a redirect to another origin',
      () async {
        final other = await TestServer.start();
        addTearDown(other.close);
        final to = Uri.encodeQueryComponent('${other.baseUrl}/echo');
        final r = await engine.send(
          req(
            '/redirect-to?u=$to',
            headers: [
              ('Authorization', 'Bearer s'),
              ('X-Api-Key', 'k'),
              ('X-Auth-Token', 't'),
              ('Cookie', 'a=b'),
              ('X-Trace', 'keep'),
            ],
          ),
        );
        final names = [
          for (final h in echoed(r)['headers'] as List)
            (h as List)[0].toString().toLowerCase(),
        ];
        expect(names, isNot(contains('x-trace')));
        expect(names, contains('user-agent'));
        expect(
          names,
          isNot(
            anyOf(
              contains('authorization'),
              contains('x-api-key'),
              contains('x-auth-token'),
              contains('cookie'),
            ),
          ),
        );
      },
    );

    test('authorization and cookie never cross origins, even when a request '
        'opts out of stripping', () async {
      final other = await TestServer.start();
      addTearDown(other.close);
      final to = Uri.encodeQueryComponent('${other.baseUrl}/echo');
      final r = await engine.send(
        req(
          '/redirect-to?u=$to',
          headers: [
            ('Authorization', 'Bearer s'),
            ('Cookie', 'a=b'),
            ('X-Api-Key', 'k'),
          ],
          settings: const HttpSettings(stripAuthCrossOrigin: false),
        ),
      );
      final names = [
        for (final h in echoed(r)['headers'] as List)
          (h as List)[0].toString().toLowerCase(),
      ];
      expect(names, isNot(contains('authorization')));
      expect(names, isNot(contains('cookie')));
      // Opting out still keeps other credential-like headers.
      expect(names, contains('x-api-key'));
    });

    test('a header with a line break is refused', () async {
      await expectLater(
        engine.send(req('/echo', headers: [('X-A', 'b\r\nX-Evil: 1')])),
        throwsA(isA<ProtocolError>()),
      );
    });

    test('a 302 turns POST into GET without a body', () async {
      final r = await engine.send(
        req(
          '/redirect/1',
          method: 'POST',
          body: utf8.encode('x'),
          headers: [('Content-Type', 'text/plain')],
        ),
      );
      expect(echoed(r)['method'], 'GET');
      expect(base64Decode(echoed(r)['bodyBase64'] as String), isEmpty);
    });
  });

  group('failures', () {
    test('times out', () async {
      expect(
        engine.send(
          req(
            '/delay/2000',
            settings: const HttpSettings(timeout: Duration(milliseconds: 150)),
          ),
        ),
        throwsA(isA<TimeoutError>()),
      );
    });

    test('cancel aborts an in-flight request', () async {
      final token = CancelToken();
      final future = engine.send(req('/delay/5000'), cancel: token);
      final expectation = expectLater(future, throwsA(isA<CancelledError>()));
      await Future<void>.delayed(const Duration(milliseconds: 100));
      token.cancel();
      await expectation;
    });

    test('connection refused is a NetworkError', () async {
      final port = server.port;
      await server.close();
      expect(
        engine.send(
          HttpRequestSpec(
            method: 'GET',
            url: Uri.parse('http://127.0.0.1:$port/'),
          ),
        ),
        throwsA(isA<NetworkError>()),
      );
    });
  });
}

void tlsTests() {
  group('TLS', () {
    late TestServer server;
    final engine = HttpEngine();
    late bool available;
    setUpAll(() async => available = await TestServer.tlsAvailable);
    setUp(() async {
      if (available) server = await TestServer.start(tls: true);
    });
    tearDown(() async {
      if (available) await server.close();
    });

    HttpRequestSpec req({required bool verify}) => HttpRequestSpec(
      method: 'GET',
      url: Uri.parse('${server.baseUrl}/echo'),
      settings: HttpSettings(verifyTls: verify),
    );

    test('a self-signed certificate is rejected when verifying', () {
      if (!available) return markTestSkipped('openssl not found');
      expect(engine.send(req(verify: true)), throwsA(isA<TlsError>()));
    });

    test('verification off accepts it and reports a TLS timing', () async {
      if (!available) return markTestSkipped('openssl not found');
      final r = await engine.send(req(verify: false));
      expect(r.status, 200);
      expect(r.timings.tls, greaterThan(Duration.zero));
    });
  });
}
