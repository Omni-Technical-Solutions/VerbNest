import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:test/test.dart';
import 'package:test_server/test_server.dart';
import 'package:verbnest_http/verbnest_http.dart';

void main() {
  late bool available;
  setUpAll(() async => available = await TestServer.tlsAvailable);

  group('host names', () {
    CertInfo info({
      List<String> names = const [],
      String subject = 'CN=a.test',
    }) => CertInfo(
      subject: subject,
      issuer: subject,
      serialHex: '01',
      notBefore: DateTime.utc(2026),
      notAfter: DateTime.utc(2027),
      names: names,
      keyAlgorithm: 'RSA 2048',
      sha256: '',
      spkiSha256: '',
      selfSigned: true,
    );

    test('subject alternative names, wildcards and IPs', () {
      final c = info(
        names: ['DNS:api.test', 'DNS:*.wild.test', 'IP:127.0.0.1'],
      );
      expect(c.coversHost('api.test'), isTrue);
      expect(c.coversHost('API.test'), isTrue);
      expect(c.coversHost('x.wild.test'), isTrue);
      expect(c.coversHost('a.b.wild.test'), isFalse);
      expect(c.coversHost('wild.test'), isFalse);
      expect(c.coversHost('127.0.0.1'), isTrue);
      expect(c.coversHost('other.test'), isFalse);
    });

    test('the common name only counts when there are no names', () {
      expect(info().coversHost('a.test'), isTrue);
      expect(info(names: ['DNS:b.test']).coversHost('a.test'), isFalse);
    });
  });

  group('a handshake', () {
    test('shows the server certificate without sending a request', () async {
      if (!available) return markTestSkipped('openssl not found');
      final server = await TestServer.start(tls: true);
      addTearDown(server.close);
      final p = await probeTls(Uri.parse('https://127.0.0.1:${server.port}/'));
      expect(p.server.subject, contains('localhost'));
      expect(p.hostMatches, isTrue);
      // Self-signed and not in the system roots.
      expect(p.trusted, isFalse);
      expect(p.clientCertificateConfigured, isFalse);
      expect(p.rejectedClientCertificate, isFalse);
      expect(
        p.server.sha256,
        matches(RegExp(r'^([0-9A-F]{2}:){31}[0-9A-F]{2}$')),
      );
      expect(server.requests, isEmpty);
    });

    test('an extra CA makes it trusted', () async {
      if (!available) return markTestSkipped('openssl not found');
      final (cert, _) = await TestServer.selfSignedCertificate();
      final server = await TestServer.start(tls: true);
      addTearDown(server.close);
      final p = await probeTls(
        Uri.parse('https://127.0.0.1:${server.port}/'),
        tls: TlsConfig(caCertificates: [Uint8List.fromList(cert)]),
      );
      expect(p.trusted, isTrue);
    });

    test('a refused connection is a TlsProbeError', () async {
      final s = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
      final port = s.port;
      await s.close();
      await expectLater(
        probeTls(Uri.parse('https://127.0.0.1:$port/')),
        throwsA(isA<TlsProbeError>()),
      );
    });

    test('a server that is not TLS is a TlsProbeError', () async {
      final s = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
      addTearDown(s.close);
      s.listen((c) {
        c.add(utf8.encode('HTTP/1.1 400 Bad Request\r\n\r\n'));
        c.close();
      });
      await expectLater(
        probeTls(Uri.parse('https://127.0.0.1:${s.port}/')),
        throwsA(isA<TlsProbeError>()),
      );
    });

    test(
      'with a client certificate: accepted, then refused when missing',
      () async {
        if (!available) return markTestSkipped('openssl not found');
        final (cert, key) = await TestServer.selfSignedCertificate();
        final (ccert, ckey) = await TestServer.selfSignedCertificate(
          cn: 'probe-client',
        );
        final context = SecurityContext()
          ..useCertificateChainBytes(cert)
          ..usePrivateKeyBytes(key)
          ..setTrustedCertificatesBytes(ccert);
        final server = await SecureServerSocket.bind(
          InternetAddress.loopbackIPv4,
          0,
          context,
          requestClientCertificate: true,
          requireClientCertificate: true,
        );
        addTearDown(server.close);
        server.listen(
          (c) => c.listen((_) {}, onError: (Object _) {}),
          onError: (Object _) {},
        );
        final url = Uri.parse('https://127.0.0.1:${server.port}/');
        final good = await probeTls(
          url,
          tls: TlsConfig(
            clientCertificates: [
              ClientCertificate(
                hostPattern: '127.0.0.1',
                certificate: Uint8List.fromList(ccert),
                privateKey: Uint8List.fromList(ckey),
                label: 'Probe',
              ),
            ],
          ),
        );
        expect(good.clientCertificateConfigured, isTrue);
        expect(good.clientCertificate!.label, 'Probe');
        expect(good.rejectedClientCertificate, isFalse);
        // Without one the server sends an alert after the handshake (TLS 1.3)
        // or the handshake itself fails (TLS 1.2); both are reported.
        try {
          final bad = await probeTls(url);
          expect(bad.rejectedClientCertificate, isTrue);
        } on TlsProbeError {
          // The handshake failed outright.
        }
      },
    );

    test('unreadable client certificate files are a TlsProbeError', () async {
      await expectLater(
        probeTls(
          Uri.parse('https://127.0.0.1:1/'),
          tls: TlsConfig(
            clientCertificates: [
              ClientCertificate(
                hostPattern: '*',
                certificate: Uint8List.fromList([1, 2, 3]),
                privateKey: Uint8List.fromList([4, 5, 6]),
              ),
            ],
          ),
        ),
        throwsA(
          isA<TlsProbeError>().having(
            (e) => e.message,
            'm',
            contains('certificates'),
          ),
        ),
      );
    });
  });
}
