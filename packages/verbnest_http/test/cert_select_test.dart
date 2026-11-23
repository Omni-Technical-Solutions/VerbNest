import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:test/test.dart';
import 'package:test_server/test_server.dart';
import 'package:verbnest_http/verbnest_http.dart';

/// Which client certificate goes to which host (FR-HTTP-013b).
ClientCertificate _c(
  String pattern, {
  bool enabled = true,
  String label = '',
}) => ClientCertificate(
  hostPattern: pattern,
  certificate: Uint8List.fromList(utf8.encode(label.isEmpty ? pattern : label)),
  privateKey: Uint8List(1),
  enabled: enabled,
  label: label.isEmpty ? pattern : label,
);

String? _pick(List<ClientCertificate> list, String host, {int? port}) =>
    TlsConfig(clientCertificates: list).selectFor(host, port: port)?.label;

void main() {
  group('patterns', () {
    test('exact, wildcard and star', () {
      expect(_c('api.test').matches('api.test'), isTrue);
      expect(_c('API.test').matches('api.TEST'), isTrue);
      expect(_c('api.test').matches('x.api.test'), isFalse);
      expect(_c('*.test').matches('a.test'), isTrue);
      expect(_c('*.test').matches('a.b.test'), isTrue);
      expect(_c('*.test').matches('test'), isFalse);
      expect(_c('*').matches('anything.example'), isTrue);
      expect(_c('').matches('anything.example'), isTrue);
    });

    test('a port in the pattern must match the port', () {
      expect(_c('api.test:8443').matches('api.test', port: 8443), isTrue);
      expect(_c('api.test:8443').matches('api.test', port: 443), isFalse);
      expect(_c('api.test:8443').matches('api.test'), isFalse);
      expect(_c('api.test').matches('api.test', port: 8443), isTrue);
      expect(_c('*.test:9000').matches('a.test', port: 9000), isTrue);
    });

    test('a scheme and a path in the pattern are ignored', () {
      expect(
        _c('https://api.test:8443/v1').matches('api.test', port: 8443),
        isTrue,
      );
      expect(_c('https://api.test').matches('api.test', port: 443), isTrue);
    });

    test('an IPv6 literal keeps its colons', () {
      expect(_c('[::1]').matches('[::1]'), isTrue);
      expect(_c('[::1]:8443').matches('[::1]', port: 8443), isTrue);
    });
  });

  group('choosing among entries', () {
    test('exact beats wildcard beats star', () {
      final list = [
        _c('*', label: 'star'),
        _c('*.test', label: 'wild'),
        _c('api.test', label: 'exact'),
      ];
      expect(_pick(list, 'api.test'), 'exact');
      expect(_pick(list, 'other.test'), 'wild');
      expect(_pick(list, 'other.example'), 'star');
    });

    test('a longer wildcard suffix beats a shorter one', () {
      final list = [
        _c('*.test', label: 'short'),
        _c('*.api.test', label: 'long'),
      ];
      expect(_pick(list, 'v1.api.test'), 'long');
      expect(_pick(list, 'v1.other.test'), 'short');
    });

    test('a pattern with a port beats the same pattern without', () {
      final list = [
        _c('api.test', label: 'plain'),
        _c('api.test:8443', label: 'port'),
      ];
      expect(_pick(list, 'api.test', port: 8443), 'port');
      expect(_pick(list, 'api.test', port: 443), 'plain');
    });

    test('the order does not matter, a tie takes the first', () {
      expect(
        _pick([
          _c('a.test', label: 'one'),
          _c('a.test', label: 'two'),
        ], 'a.test'),
        'one',
      );
      expect(
        _pick(
          [_c('a.test', label: 'x'), _c('*', label: 'y')].reversed.toList(),
          'a.test',
        ),
        'x',
      );
    });

    test('a switched-off entry never matches', () {
      final list = [
        _c('a.test', enabled: false, label: 'off'),
        _c('*', label: 'star'),
      ];
      expect(_pick(list, 'a.test'), 'star');
      expect(_pick([_c('a.test', enabled: false)], 'a.test'), isNull);
    });

    test('a none entry stops a broader one, and only for its hosts', () {
      final none = ClientCertificate.none('internal.test', label: 'no cert');
      final config = TlsConfig(
        clientCertificates: [
          _c('*', label: 'star'),
          none,
        ],
      );
      expect(config.selectFor('internal.test')!.isNone, isTrue);
      expect(config.clientCertificateFor('internal.test'), isNull);
      expect(config.clientCertificateFor('api.test')!.label, 'star');
      // Switched off, the none entry stops nothing.
      final off = TlsConfig(
        clientCertificates: [
          _c('*', label: 'star'),
          ClientCertificate.none('internal.test', enabled: false),
        ],
      );
      expect(off.clientCertificateFor('internal.test')!.label, 'star');
    });

    test('nothing matches: nothing is chosen', () {
      expect(_pick([_c('a.test')], 'b.test'), isNull);
      expect(_pick(const [], 'b.test'), isNull);
    });
  });

  group('on the wire', () {
    late bool available;
    setUpAll(() async => available = await TestServer.tlsAvailable);

    /// An HTTPS server that insists on a client certificate and answers with
    /// the subject it saw.
    Future<SecureServerSocket> server(List<int> trusted) async {
      final (cert, key) = await TestServer.selfSignedCertificate();
      final context = SecurityContext()
        ..useCertificateChainBytes(cert)
        ..usePrivateKeyBytes(key)
        ..setTrustedCertificatesBytes(trusted);
      final s = await SecureServerSocket.bind(
        InternetAddress.loopbackIPv4,
        0,
        context,
        requestClientCertificate: true,
        requireClientCertificate: true,
      );
      s.listen((c) {
        final buf = BytesBuilder();
        c.listen((d) async {
          buf.add(d);
          if (!latin1.decode(buf.toBytes()).contains('\r\n\r\n')) return;
          final who = c.peerCertificate?.subject ?? 'none';
          c.add(
            utf8.encode(
              'HTTP/1.1 200 OK\r\nContent-Length: ${who.length}\r\nConnection: close\r\n\r\n$who',
            ),
          );
          await c.close();
        }, onError: (Object _) {});
      }, onError: (Object _) {});
      addTearDown(() => s.close());
      return s;
    }

    ClientCertificate entry(
      String pattern,
      (List<int>, List<int>) pair,
      String label,
    ) => ClientCertificate(
      hostPattern: pattern,
      certificate: Uint8List.fromList(pair.$1),
      privateKey: Uint8List.fromList(pair.$2),
      label: label,
    );

    Future<HttpResponseRecord> get(int port, List<ClientCertificate> list) =>
        HttpEngine().send(
          HttpRequestSpec(
            method: 'GET',
            url: Uri.parse('https://127.0.0.1:$port/'),
            settings: HttpSettings(
              verifyTls: false,
              tls: TlsConfig(clientCertificates: list),
            ),
          ),
        );

    test('the most specific entry is the one presented', () async {
      if (!available) return markTestSkipped('openssl not found');
      final a = await TestServer.selfSignedCertificate(cn: 'broad-cert');
      final b = await TestServer.selfSignedCertificate(cn: 'exact-cert');
      final s = await server(b.$1);
      final r = await get(s.port, [
        entry('*', a, 'Broad'),
        entry('127.0.0.1:${s.port}', b, 'Exact'),
      ]);
      expect(r.bodyText, contains('exact-cert'));
      expect(r.tls!.clientCertificateSent, isTrue);
      expect(r.tls!.clientCertificateLabel, 'Exact');
    });

    test(
      'a none entry sends no certificate, which this server refuses',
      () async {
        if (!available) return markTestSkipped('openssl not found');
        final a = await TestServer.selfSignedCertificate(cn: 'broad-cert');
        final s = await server(a.$1);
        await expectLater(
          get(s.port, [
            entry('*', a, 'Broad'),
            ClientCertificate.none('127.0.0.1'),
          ]),
          throwsA(isA<HttpEngineError>()),
        );
      },
    );

    test('a switched-off entry is not presented', () async {
      if (!available) return markTestSkipped('openssl not found');
      final a = await TestServer.selfSignedCertificate(cn: 'broad-cert');
      final s = await server(a.$1);
      final off = ClientCertificate(
        hostPattern: '*',
        certificate: Uint8List.fromList(a.$1),
        privateKey: Uint8List.fromList(a.$2),
        enabled: false,
      );
      await expectLater(get(s.port, [off]), throwsA(isA<HttpEngineError>()));
    });
  });
}
