import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:verbnest_core/verbnest_core.dart';
import 'package:verbnest_http/verbnest_http.dart';
import 'package:test/test.dart';
import 'package:test_server/test_server.dart';

/// A stand-in proxy that records what it was asked and tunnels for real.
class FakeProxy {
  FakeProxy._(this.server);

  final ServerSocket server;
  final heads = <String>[];
  final socksTargets = <String>[];
  String? socksUser;

  /// Required `user:password`, or null for none.
  String? auth;

  int get port => server.port;

  static Future<FakeProxy> http({String? auth}) async {
    final p = FakeProxy._(
      await ServerSocket.bind(InternetAddress.loopbackIPv4, 0),
    );
    p.auth = auth;
    p.server.listen(p._httpConn);
    return p;
  }

  static Future<FakeProxy> socks5({String? auth}) async {
    final p = FakeProxy._(
      await ServerSocket.bind(InternetAddress.loopbackIPv4, 0),
    );
    p.auth = auth;
    p.server.listen(p._socksConn);
    return p;
  }

  Future<void> close() => server.close();

  void _httpConn(Socket c) {
    final buf = BytesBuilder();
    late StreamSubscription<Uint8List> sub;
    sub = c.listen((d) async {
      buf.add(d);
      final text = latin1.decode(buf.toBytes());
      if (!text.contains('\r\n\r\n')) return;
      sub.pause();
      final head = text.substring(0, text.indexOf('\r\n\r\n'));
      heads.add(head);
      final expected = auth == null
          ? null
          : 'Basic ${base64Encode(utf8.encode(auth!))}';
      final given = RegExp(
        r'proxy-authorization: (.*)',
        caseSensitive: false,
      ).firstMatch(head)?[1]?.trim();
      if (expected != null && given != expected) {
        c.add(
          utf8.encode(
            'HTTP/1.1 407 Proxy Authentication Required\r\n'
            'Content-Length: 0\r\n\r\n',
          ),
        );
        await c.close();
        return;
      }
      if (head.startsWith('CONNECT ')) {
        final target = head.split(' ')[1];
        final i = target.lastIndexOf(':');
        final up = await Socket.connect(
          target.substring(0, i),
          int.parse(target.substring(i + 1)),
        );
        c.add(utf8.encode('HTTP/1.1 200 Connection established\r\n\r\n'));
        sub
          ..onData(up.add)
          ..onDone(up.destroy)
          ..resume();
        up.listen(c.add, onDone: c.destroy, onError: (_) => c.destroy());
      } else {
        const body = 'via-proxy';
        c.add(
          utf8.encode(
            'HTTP/1.1 200 OK\r\nContent-Length: ${body.length}\r\n'
            'Connection: close\r\n\r\n$body',
          ),
        );
        await c.close();
      }
    });
  }

  void _socksConn(Socket c) {
    final it = StreamIterator<Uint8List>(c);
    var left = <int>[];
    Future<List<int>> take(int n) async {
      while (left.length < n) {
        if (!await it.moveNext()) throw StateError('closed');
        left.addAll(it.current);
      }
      final out = left.sublist(0, n);
      left = left.sublist(n);
      return out;
    }

    () async {
      try {
        final hello = await take(2);
        final methods = await take(hello[1]);
        if (auth != null) {
          if (!methods.contains(2)) {
            c.add([5, 0xFF]);
            await c.close();
            return;
          }
          c.add([5, 2]);
          final ver = await take(2);
          final user = utf8.decode(await take(ver[1]));
          final plen = (await take(1))[0];
          final pass = utf8.decode(await take(plen));
          socksUser = user;
          if ('$user:$pass' != auth) {
            c.add([1, 1]);
            await c.close();
            return;
          }
          c.add([1, 0]);
        } else {
          c.add([5, 0]);
        }
        final req = await take(4);
        String host;
        switch (req[3]) {
          case 1:
            host = (await take(4)).join('.');
          case 3:
            host = utf8.decode(await take((await take(1))[0]));
          default:
            await take(16);
            host = '::1';
        }
        final p = await take(2);
        final port = (p[0] << 8) | p[1];
        socksTargets.add('$host:$port');
        final up = await Socket.connect(host, port);
        c.add([5, 0, 0, 1, 0, 0, 0, 0, 0, 0]);
        // Anything the client sent after the request is forwarded as is.
        if (left.isNotEmpty) up.add(left);
        _pipeIterator(c, up, it);
      } catch (_) {
        c.destroy();
      }
    }();
  }

  void _pipeIterator(Socket a, Socket b, StreamIterator<Uint8List> it) {
    () async {
      try {
        while (await it.moveNext()) {
          b.add(it.current);
        }
      } catch (_) {}
      b.destroy();
    }();
    b.listen(a.add, onDone: a.destroy, onError: (_) => a.destroy());
  }
}

/// A plain HTTP server for cookie tests.
Future<HttpServer> cookieServer() async {
  final s = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
  s.listen((req) async {
    switch (req.uri.path) {
      case '/set':
        req.response.headers.add('Set-Cookie', 'sid=abc; Path=/');
        req.response.headers.add(
          'Set-Cookie',
          'theme=dark; Path=/; Max-Age=60',
        );
        req.response.write('set');
      case '/redir':
        req.response.statusCode = 302;
        req.response.headers.add('Set-Cookie', 'hop=1; Path=/');
        req.response.headers.set('Location', '/echo');
      default:
        req.response.write(req.headers.value('cookie') ?? '');
    }
    await req.response.close();
  });
  return s;
}

void main() {
  group('cookies', () {
    late HttpServer server;
    late CookieJar jar;
    late HttpEngine engine;
    setUp(() async {
      server = await cookieServer();
      jar = CookieJar();
      engine = HttpEngine(cookieJar: jar);
    });
    tearDown(() => server.close(force: true));

    HttpRequestSpec req(
      String path, {
      HttpSettings settings = const HttpSettings(),
      List<Header> headers = const [],
    }) => HttpRequestSpec(
      method: 'GET',
      url: Uri.parse('http://127.0.0.1:${server.port}$path'),
      settings: settings,
      headers: headers,
    );

    test('cookies are stored and sent back automatically', () async {
      await engine.send(req('/set'));
      expect(jar.cookies.map((c) => c.name).toSet(), {'sid', 'theme'});
      final r = await engine.send(req('/echo'));
      expect(r.bodyText, 'sid=abc; theme=dark');
      expect(r.sent.head, contains('Cookie: sid=abc; theme=dark'));
    });

    test('cookies set by a redirect are sent on the next hop', () async {
      final r = await engine.send(req('/redir'));
      expect(r.bodyText, 'hop=1');
      expect(r.redirects.length, 1);
    });

    test('turning cookies off neither stores nor sends', () async {
      const off = HttpSettings(sendCookies: false);
      await engine.send(req('/set', settings: off));
      expect(jar.isEmpty, isTrue);
      await engine.send(req('/set'));
      final r = await engine.send(req('/echo', settings: off));
      expect(r.bodyText, '');
    });

    test('a Cookie header written by the user wins', () async {
      await engine.send(req('/set'));
      final r = await engine.send(
        req('/echo', headers: [('Cookie', 'mine=1')]),
      );
      expect(r.bodyText, 'mine=1');
    });

    test('an engine without a jar does nothing with cookies', () async {
      final plain = HttpEngine();
      await plain.send(req('/set'));
      expect((await plain.send(req('/echo'))).bodyText, '');
    });
  });

  group('proxy configuration', () {
    test('bypass patterns', () {
      const p = ProxyConfig(
        kind: ProxyKind.http,
        host: 'p',
        port: 1,
        bypass: ['localhost', '*.internal.test', '.corp.test', '10.0.0.5'],
      );
      expect(p.bypasses('localhost'), isTrue);
      expect(p.bypasses('a.internal.test'), isTrue);
      expect(p.bypasses('internal.test'), isTrue);
      expect(p.bypasses('x.corp.test'), isTrue);
      expect(p.bypasses('10.0.0.5'), isTrue);
      expect(p.bypasses('notlocalhost'), isFalse);
      expect(p.bypasses('example.com'), isFalse);
      expect(p.copyWith(bypass: ['*']).bypasses('anything'), isTrue);
    });

    test('environment variables', () {
      final env = {
        'HTTP_PROXY': 'http://user:p%40ss@proxy.test:3128',
        'https_proxy': 'socks5://s.test',
        'NO_PROXY': 'skip.test, .lan',
      };
      final http = ProxyConfig.fromEnvironment(
        Uri.parse('http://a.test/'),
        env,
      )!;
      expect(
        (http.kind, http.host, http.port),
        (ProxyKind.http, 'proxy.test', 3128),
      );
      expect((http.username, http.password), ('user', 'p@ss'));
      final https = ProxyConfig.fromEnvironment(
        Uri.parse('https://a.test/'),
        env,
      )!;
      expect((https.kind, https.port), (ProxyKind.socks5, 1080));
      expect(
        ProxyConfig.fromEnvironment(Uri.parse('http://skip.test/'), env),
        isNull,
      );
      expect(
        ProxyConfig.fromEnvironment(Uri.parse('http://h.lan/'), env),
        isNull,
      );
      expect(
        ProxyConfig.fromEnvironment(Uri.parse('http://a.test/'), {}),
        isNull,
      );
    });
  });

  group('proxy traffic', () {
    late TestServer target;
    late FakeProxy proxy;
    setUp(() async => target = await TestServer.start());
    tearDown(() async {
      await target.close();
      await proxy.close();
    });

    ProxyConfig cfg(
      ProxyKind kind, {
      String user = '',
      String pass = '',
      List<String> bypass = const [],
    }) => ProxyConfig(
      kind: kind,
      host: '127.0.0.1',
      port: proxy.port,
      username: user,
      password: pass,
      bypass: bypass,
    );

    HttpRequestSpec req(String url, ProxyConfig p, {bool verify = true}) =>
        HttpRequestSpec(
          method: 'GET',
          url: Uri.parse(url),
          settings: HttpSettings(proxy: p, verifyTls: verify),
        );

    test(
      'plain HTTP goes to the proxy in absolute form with credentials',
      () async {
        proxy = await FakeProxy.http(auth: 'ann:pw');
        final r = await HttpEngine().send(
          req(
            'http://example.test/a?b=1',
            cfg(ProxyKind.http, user: 'ann', pass: 'pw'),
          ),
        );
        expect(r.bodyText, 'via-proxy');
        expect(
          proxy.heads.single,
          startsWith('GET http://example.test/a?b=1 HTTP/1.1'),
        );
        expect(r.sent.head, contains('Proxy-Authorization: Basic'));
      },
    );

    test('wrong proxy credentials give 407 back', () async {
      proxy = await FakeProxy.http(auth: 'ann:pw');
      final r = await HttpEngine().send(
        req(
          'http://example.test/',
          cfg(ProxyKind.http, user: 'ann', pass: 'bad'),
        ),
      );
      expect(r.status, 407);
    });

    test('hosts on the bypass list go direct', () async {
      proxy = await FakeProxy.http();
      final r = await HttpEngine().send(
        req(
          '${target.baseUrl}/echo',
          cfg(ProxyKind.http, bypass: ['127.0.0.1']),
        ),
      );
      expect(r.status, 200);
      expect(r.bodyText, isNot('via-proxy'));
      expect(proxy.heads, isEmpty);
    });

    test('the system proxy comes from the environment', () async {
      proxy = await FakeProxy.http();
      final engine = HttpEngine(
        environment: {'HTTP_PROXY': 'http://127.0.0.1:${proxy.port}'},
      );
      final r = await engine.send(
        HttpRequestSpec(
          method: 'GET',
          url: Uri.parse('http://example.test/'),
          settings: const HttpSettings(useSystemProxy: true),
        ),
      );
      expect(r.bodyText, 'via-proxy');
    });

    test(
      'SOCKS5 without log-in reaches the target and sends the host name',
      () async {
        proxy = await FakeProxy.socks5();
        final r = await HttpEngine().send(
          req('http://localhost:${target.port}/echo', cfg(ProxyKind.socks5)),
        );
        expect(r.status, 200);
        expect(proxy.socksTargets.single, 'localhost:${target.port}');
      },
    );

    test('SOCKS5 with user name and password', () async {
      proxy = await FakeProxy.socks5(auth: 'bob:secret');
      final ok = await HttpEngine().send(
        req(
          '${target.baseUrl}/echo',
          cfg(ProxyKind.socks5, user: 'bob', pass: 'secret'),
        ),
      );
      expect(ok.status, 200);
      expect(proxy.socksUser, 'bob');
      await expectLater(
        HttpEngine().send(
          req(
            '${target.baseUrl}/echo',
            cfg(ProxyKind.socks5, user: 'bob', pass: 'no'),
          ),
        ),
        throwsA(
          isA<NetworkError>().having(
            (e) => e.message,
            'm',
            contains('rejected'),
          ),
        ),
      );
      await expectLater(
        HttpEngine().send(req('${target.baseUrl}/echo', cfg(ProxyKind.socks5))),
        throwsA(isA<NetworkError>()),
      );
    });

    test('a refused SOCKS5 connection is explained', () async {
      proxy = await FakeProxy.socks5();
      final dead = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
      final port = dead.port;
      await dead.close();
      await expectLater(
        HttpEngine().send(
          req('http://127.0.0.1:$port/', cfg(ProxyKind.socks5)),
        ),
        throwsA(isA<NetworkError>()),
      );
    });

    group('HTTPS through a proxy', () {
      var available = false;
      late TestServer tls;
      setUpAll(() async => available = await TestServer.tlsAvailable);
      setUp(() async {
        if (available) tls = await TestServer.start(tls: true);
      });
      tearDown(() async {
        if (available) await tls.close();
      });

      test('CONNECT tunnels TLS and reports the certificate', () async {
        if (!available) return markTestSkipped('openssl not found');
        proxy = await FakeProxy.http(auth: 'ann:pw');
        final r = await HttpEngine().send(
          req(
            '${tls.baseUrl}/echo',
            cfg(ProxyKind.http, user: 'ann', pass: 'pw'),
            verify: false,
          ),
        );
        expect(r.status, 200);
        expect(
          proxy.heads.single,
          startsWith('CONNECT 127.0.0.1:${tls.port} '),
        );
        expect(r.tls!.subject, contains('localhost'));
        expect(r.timings.tls, greaterThan(Duration.zero));
      });

      test('a refused tunnel is reported', () async {
        if (!available) return markTestSkipped('openssl not found');
        proxy = await FakeProxy.http(auth: 'ann:pw');
        await expectLater(
          HttpEngine().send(
            req('${tls.baseUrl}/echo', cfg(ProxyKind.http), verify: false),
          ),
          throwsA(
            isA<NetworkError>().having((e) => e.message, 'm', contains('407')),
          ),
        );
      });

      test('SOCKS5 carries TLS too', () async {
        if (!available) return markTestSkipped('openssl not found');
        proxy = await FakeProxy.socks5();
        final r = await HttpEngine().send(
          req('${tls.baseUrl}/echo', cfg(ProxyKind.socks5), verify: false),
        );
        expect(r.status, 200);
        expect(proxy.socksTargets.single, '127.0.0.1:${tls.port}');
      });
    });
  });

  group('certificates', () {
    var available = false;
    setUpAll(() async => available = await TestServer.tlsAvailable);

    test(
      'a custom CA makes a self-signed server trusted and TLS info is shown',
      () async {
        if (!available) return markTestSkipped('openssl not found');
        final server = await TestServer.start(tls: true);
        addTearDown(server.close);
        final (cert, _) = await TestServer.selfSignedCertificate();
        HttpRequestSpec spec(TlsConfig? tls) => HttpRequestSpec(
          method: 'GET',
          url: Uri.parse('${server.baseUrl}/echo'),
          settings: HttpSettings(tls: tls),
        );
        await expectLater(
          HttpEngine().send(spec(null)),
          throwsA(isA<TlsError>()),
        );
        final r = await HttpEngine().send(
          spec(TlsConfig(caCertificates: [Uint8List.fromList(cert)])),
        );
        expect(r.status, 200);
        expect(r.tls!.subject, contains('localhost'));
        expect(r.tls!.validTo.isAfter(r.tls!.validFrom), isTrue);
        expect(r.tls!.clientCertificateSent, isFalse);
      },
    );

    /// An HTTPS server that insists on a client certificate and answers
    /// with the subject it saw.
    Future<(SecureServerSocket, TlsConfig Function(ClientCertificate))>
    mutualTlsServer(List<int> trustedClientCert) async {
      final (cert, key) = await TestServer.selfSignedCertificate();
      final context = SecurityContext()
        ..useCertificateChainBytes(cert)
        ..usePrivateKeyBytes(key)
        ..setTrustedCertificatesBytes(trustedClientCert);
      final server = await SecureServerSocket.bind(
        InternetAddress.loopbackIPv4,
        0,
        context,
        requestClientCertificate: true,
        requireClientCertificate: true,
      );
      server.listen((s) {
        final buf = BytesBuilder();
        s.listen((d) async {
          buf.add(d);
          if (!latin1.decode(buf.toBytes()).contains('\r\n\r\n')) return;
          final who = s.peerCertificate?.subject ?? 'none';
          s.add(
            utf8.encode(
              'HTTP/1.1 200 OK\r\nContent-Length: ${who.length}\r\n'
              'Connection: close\r\n\r\n$who',
            ),
          );
          await s.close();
        }, onError: (Object _) {});
      }, onError: (Object _) {});
      addTearDown(() => server.close());
      return (
        server,
        (ClientCertificate c) => TlsConfig(clientCertificates: [c]),
      );
    }

    HttpRequestSpec mtlsReq(int port, TlsConfig tls) => HttpRequestSpec(
      method: 'GET',
      url: Uri.parse('https://127.0.0.1:$port/'),
      settings: HttpSettings(verifyTls: false, tls: tls),
    );

    test('a PEM client certificate is presented to matching hosts', () async {
      if (!available) return markTestSkipped('openssl not found');
      final (ccert, ckey) = await TestServer.selfSignedCertificate(
        cn: 'client1',
      );
      final (server, make) = await mutualTlsServer(ccert);
      final cert = ClientCertificate(
        hostPattern: '127.0.0.1',
        certificate: Uint8List.fromList(ccert),
        privateKey: Uint8List.fromList(ckey),
      );
      final r = await HttpEngine().send(mtlsReq(server.port, make(cert)));
      expect(r.bodyText, contains('client1'));
      expect(r.tls!.clientCertificateSent, isTrue);

      final other = ClientCertificate(
        hostPattern: '*.other.test',
        certificate: cert.certificate,
        privateKey: cert.privateKey,
      );
      await expectLater(
        HttpEngine().send(mtlsReq(server.port, make(other))),
        throwsA(isA<HttpEngineError>()),
      );
    });

    test('a PKCS#12 bundle needs the right passphrase', () async {
      if (!available) return markTestSkipped('openssl not found');
      final (ccert, ckey) = await TestServer.selfSignedCertificate(
        cn: 'client2',
      );
      final p12 = Uint8List.fromList(
        await TestServer.pkcs12(ccert, ckey, 'hunter2'),
      );
      final (server, make) = await mutualTlsServer(ccert);
      ClientCertificate bundle(String pass) => ClientCertificate(
        hostPattern: '*',
        certificate: p12,
        passphrase: pass,
      );
      final r = await HttpEngine().send(
        mtlsReq(server.port, make(bundle('hunter2'))),
      );
      expect(r.bodyText, contains('client2'));
      await expectLater(
        HttpEngine().send(mtlsReq(server.port, make(bundle('wrong')))),
        throwsA(
          isA<TlsError>().having(
            (e) => e.message,
            'm',
            contains('certificates'),
          ),
        ),
      );
    });

    test('host patterns', () {
      ClientCertificate c(String p) =>
          ClientCertificate(hostPattern: p, certificate: Uint8List(0));
      expect(c('*').matches('x.test'), isTrue);
      expect(c('*.test').matches('a.test'), isTrue);
      expect(c('*.test').matches('test'), isFalse);
      expect(c('A.test').matches('a.TEST'), isTrue);
      expect(c('a.test').matches('b.test'), isFalse);
    });
  });
}
