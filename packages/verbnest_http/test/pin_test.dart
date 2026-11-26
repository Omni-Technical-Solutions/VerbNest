import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:test/test.dart';
import 'package:test_server/test_server.dart';
import 'package:verbnest_http/verbnest_http.dart';

CertInfo _info({String spki = 'AA', String leaf = 'BB'}) => CertInfo(
  subject: 'CN=host.test',
  issuer: 'CN=host.test',
  serialHex: '01',
  notBefore: DateTime.utc(2026),
  notAfter: DateTime.utc(2027, 3, 1),
  names: const ['DNS:host.test'],
  keyAlgorithm: 'RSA 2048',
  sha256: leaf,
  spkiSha256: spki,
  selfSigned: true,
);

final _sha = List.generate(
  32,
  (i) => i.toRadixString(16).padLeft(2, '0').toUpperCase(),
).join(':');

/// Pinning the server key (FR-HTTP-013d).
void main() {
  group('fingerprints', () {
    test('any common spelling is normalised', () {
      final plain = _sha.replaceAll(':', '');
      expect(normalizeFingerprint(plain), _sha);
      expect(normalizeFingerprint(plain.toLowerCase()), _sha);
      expect(normalizeFingerprint(_sha.toLowerCase()), _sha);
      expect(normalizeFingerprint(' $_sha '), _sha);
      expect(normalizeFingerprint('nonsense'), 'NONSENSE');
    });
  });

  group('the pin list', () {
    test('lookup, replace, remove and the change callback', () {
      final changes = <int>[];
      final book = PinBook([], (e) => changes.add(e.length));
      final a = PinEntry(host: 'Api.Test', spki: _sha);
      book.put(
        PinEntry.firstUse(
          'Api.Test',
          443,
          _info(spki: _sha),
          DateTime.utc(2026, 11),
        ),
      );
      expect(book.lookup('API.test', 443), isNotNull);
      expect(book.lookup('api.test', 8443), isNull);
      book.put(
        PinEntry.firstUse(
          'api.test',
          443,
          _info(spki: 'CC'),
          DateTime.utc(2026, 11),
        ),
      );
      expect(book.entries, hasLength(1));
      expect(book.lookup('api.test', 443)!.spki, 'CC');
      book.remove('api.test', 443);
      expect(book.entries, isEmpty);
      expect(changes, [1, 1, 0]);
      expect(a.label, 'Api.Test');
      expect(PinEntry(host: 'h', port: 8443, spki: 'x').label, 'h:8443');
    });

    test('an entry survives JSON', () {
      final e = PinEntry.firstUse(
        'api.test',
        8443,
        _info(spki: _sha, leaf: 'LL'),
        DateTime.utc(2026, 11, 3),
      ).copyWith(enabled: false, manual: true);
      final back = PinEntry.fromJson(e.toJson());
      expect(back.host, 'api.test');
      expect(back.port, 8443);
      expect(back.spki, _sha);
      expect(back.leaf, 'LL');
      expect(back.subject, 'CN=host.test');
      expect(back.notAfter, DateTime.utc(2027, 3, 1));
      expect(back.firstSeen, DateTime.utc(2026, 11, 3));
      expect(back.enabled, isFalse);
      expect(back.manual, isTrue);
      // Defaults are not written.
      expect(PinEntry(host: 'h', spki: 'x').toJson().keys, ['host', 'spki']);
    });

    test('a pin given as a certificate hash matches the certificate', () {
      final e = PinEntry(
        host: 'h',
        spki: 'NOPE',
        leaf: _sha.toLowerCase(),
        manual: true,
      );
      expect(e.matches(_info(leaf: _sha)), isTrue);
      expect(e.matches(_info(leaf: 'other')), isFalse);
    });
  });

  group('the decision', () {
    ClientCertificate cert(String pattern) => ClientCertificate(
      hostPattern: pattern,
      certificate: Uint8List(1),
      privateKey: Uint8List(1),
    );

    TlsConfig config(
      PinBook book, {
      bool byDefault = true,
      List<ClientCertificate>? certs,
    }) => TlsConfig(
      pins: book,
      pinByDefault: byDefault,
      clientCertificates: certs ?? [cert('*')],
    );

    test('a host with a client certificate is pinned on first use', () {
      final book = PinBook();
      final r = checkPin(
        config(book),
        'host.test',
        443,
        _info(spki: 'K1'),
        verified: true,
      );
      expect(r.status, PinStatus.recorded);
      expect(book.lookup('host.test', 443)!.spki, 'K1');
      expect(book.lookup('host.test', 443)!.firstSeen, isNotNull);
      expect(
        checkPin(
          config(book),
          'host.test',
          443,
          _info(spki: 'K1'),
          verified: true,
        ).status,
        PinStatus.matches,
      );
      final bad = checkPin(
        config(book),
        'host.test',
        443,
        _info(spki: 'K2'),
        verified: true,
      );
      expect(bad.status, PinStatus.mismatch);
      expect(bad.entry!.spki, 'K1');
    });

    test('a host without a client certificate or a pin is left alone', () {
      final book = PinBook();
      expect(
        checkPin(
          config(book, certs: [cert('other.test')]),
          'host.test',
          443,
          _info(),
          verified: true,
        ).status,
        PinStatus.notApplicable,
      );
      expect(book.entries, isEmpty);
      expect(
        checkPin(
          config(book, byDefault: false),
          'host.test',
          443,
          _info(),
          verified: true,
        ).status,
        PinStatus.notApplicable,
      );
      expect(
        checkPin(
          const TlsConfig(),
          'host.test',
          443,
          _info(),
          verified: true,
        ).status,
        PinStatus.notApplicable,
      );
      expect(
        checkPin(null, 'host.test', 443, _info(), verified: true).status,
        PinStatus.notApplicable,
      );
    });

    test('a none entry means no client certificate, so no default pin', () {
      final book = PinBook();
      final tls = config(
        book,
        certs: [cert('*'), ClientCertificate.none('host.test')],
      );
      expect(
        checkPin(tls, 'host.test', 443, _info(), verified: true).status,
        PinStatus.notApplicable,
      );
      expect(
        checkPin(tls, 'other.test', 443, _info(), verified: true).status,
        PinStatus.recorded,
      );
    });

    test('trustChanges replaces a recorded key but not a manual one', () {
      final seen = <PinEntry>[];
      final book =
          PinBook([
              PinEntry(host: 'a.test', spki: 'K1'),
              PinEntry(host: 'm.test', spki: 'K1', manual: true),
            ])
            ..trustChanges = true
            ..onMismatch = (p, _) => seen.add(p);
      final tls = TlsConfig(pins: book);
      final a = checkPin(tls, 'a.test', 443, _info(spki: 'K2'), verified: true);
      expect(a.status, PinStatus.recorded);
      expect(book.lookup('a.test', 443)!.spki, 'K2');
      expect(seen, isEmpty);
      final m = checkPin(tls, 'm.test', 443, _info(spki: 'K2'), verified: true);
      expect(m.status, PinStatus.mismatch);
      expect(book.lookup('m.test', 443)!.spki, 'K1');
      expect(seen.single.host, 'm.test');
    });

    test('a pin of its own applies without a client certificate', () {
      final book = PinBook([
        PinEntry(host: 'host.test', spki: 'K1', manual: true),
      ]);
      final tls = TlsConfig(pins: book, pinByDefault: false);
      expect(
        checkPin(
          tls,
          'host.test',
          443,
          _info(spki: 'K1'),
          verified: true,
        ).status,
        PinStatus.matches,
      );
      expect(
        checkPin(
          tls,
          'host.test',
          443,
          _info(spki: 'K2'),
          verified: true,
        ).status,
        PinStatus.mismatch,
      );
      // Another port is another host.
      expect(
        checkPin(
          tls,
          'host.test',
          8443,
          _info(spki: 'K2'),
          verified: true,
        ).status,
        PinStatus.notApplicable,
      );
    });

    test('an unreadable certificate is refused only under an enabled pin', () {
      final pinned = PinBook([PinEntry(host: 'host.test', spki: 'K1')]);
      expect(
        pinRequired(config(pinned), 'host.test', 443, verified: true),
        isNotNull,
      );
      // No entry for the host, verification off, a disabled entry, no book:
      // there is nothing to compare, so nothing is refused.
      expect(
        pinRequired(config(pinned), 'other.test', 443, verified: true),
        isNull,
      );
      expect(
        pinRequired(config(pinned), 'host.test', 443, verified: false),
        isNull,
      );
      final off = PinBook([
        PinEntry(host: 'host.test', spki: 'K1', enabled: false),
      ]);
      expect(
        pinRequired(config(off), 'host.test', 443, verified: true),
        isNull,
      );
      expect(pinRequired(null, 'host.test', 443, verified: true), isNull);
      expect(
        pinUnreadableMessage('host.test', 443),
        contains('host.test:443 could not be read'),
      );
    });

    test('nothing is recorded or compared without verification', () {
      final book = PinBook([PinEntry(host: 'host.test', spki: 'K1')]);
      expect(
        checkPin(
          config(book),
          'host.test',
          443,
          _info(spki: 'K2'),
          verified: false,
        ).status,
        PinStatus.unverified,
      );
      final empty = PinBook();
      expect(
        checkPin(
          config(empty),
          'new.test',
          443,
          _info(),
          verified: false,
        ).status,
        PinStatus.unverified,
      );
      expect(empty.entries, isEmpty);
    });

    test('a switched-off pin is not checked', () {
      final book = PinBook([
        PinEntry(host: 'host.test', spki: 'K1', enabled: false),
      ]);
      expect(
        checkPin(
          config(book),
          'host.test',
          443,
          _info(spki: 'K2'),
          verified: true,
        ).status,
        PinStatus.disabled,
      );
    });

    test('a renewed certificate with the same key updates the details', () {
      final book = PinBook();
      checkPin(
        config(book),
        'host.test',
        443,
        _info(spki: 'K1', leaf: 'L1'),
        verified: true,
      );
      final r = checkPin(
        config(book),
        'host.test',
        443,
        _info(spki: 'K1', leaf: 'L2'),
        verified: true,
      );
      expect(r.status, PinStatus.matches);
      expect(book.lookup('host.test', 443)!.leaf, 'L2');
      // A pin the person made is not rewritten.
      final manual = PinBook([
        PinEntry(host: 'host.test', spki: 'K1', leaf: 'L1', manual: true),
      ]);
      checkPin(
        config(manual),
        'host.test',
        443,
        _info(spki: 'K1', leaf: 'L9'),
        verified: true,
      );
      expect(manual.lookup('host.test', 443)!.leaf, 'L1');
    });

    test('record: false only compares', () {
      final book = PinBook();
      checkPin(
        config(book),
        'host.test',
        443,
        _info(),
        verified: true,
        record: false,
      );
      expect(book.entries, isEmpty);
    });

    test('the mismatch message names both keys and the dates', () {
      final e = PinMismatchError(
        PinEntry.firstUse(
          'host.test',
          443,
          _info(spki: 'OLD'),
          DateTime.utc(2026),
        ),
        _info(spki: 'NEW'),
      );
      expect(e.message, contains('host.test changed'));
      expect(e.message, contains('OLD'));
      expect(e.message, contains('NEW'));
      expect(e.message, contains('expires 2027-03-01'));
    });
  });

  group('on the wire', () {
    late bool available;
    setUpAll(() async => available = await TestServer.tlsAvailable);

    late Directory dir;
    setUp(() => dir = Directory.systemTemp.createTempSync('verbnest-pin'));
    tearDown(() => dir.deleteSync(recursive: true));

    Future<bool> openssl(List<String> a) async {
      try {
        return (await Process.run('openssl', a)).exitCode == 0;
      } on ProcessException {
        return false;
      }
    }

    /// A TLS server that answers every request with "ok".
    Future<SecureServerSocket> serve(List<int> cert, List<int> key) async {
      final context = SecurityContext()
        ..useCertificateChainBytes(cert)
        ..usePrivateKeyBytes(key);
      final s = await SecureServerSocket.bind(
        InternetAddress.loopbackIPv4,
        0,
        context,
      );
      s.listen((c) {
        final buf = BytesBuilder();
        c.listen((d) async {
          buf.add(d);
          if (!latin1.decode(buf.toBytes()).contains('\r\n\r\n')) return;
          c.add(
            utf8.encode(
              'HTTP/1.1 200 OK\r\nContent-Length: 2\r\nConnection: close\r\n\r\nok',
            ),
          );
          await c.close();
        }, onError: (Object _) {});
      }, onError: (Object _) {});
      addTearDown(s.close);
      return s;
    }

    Future<HttpResponseRecord> get(
      int port,
      TlsConfig tls, {
      bool verify = false,
    }) => HttpEngine().send(
      HttpRequestSpec(
        method: 'GET',
        url: Uri.parse('https://127.0.0.1:$port/'),
        settings: HttpSettings(verifyTls: verify, tls: tls),
      ),
    );

    Future<(TlsConfig, PinBook)> trusting(
      List<int> serverCert, {
      List<PinEntry> pins = const [],
    }) async {
      final book = PinBook(pins);
      final (cc, ck) = await TestServer.selfSignedCertificate(cn: 'pin-client');
      return (
        TlsConfig(
          // Trust the server's own certificate so verification can stay on.
          caCertificates: [Uint8List.fromList(serverCert)],
          clientCertificates: [
            ClientCertificate(
              hostPattern: '127.0.0.1',
              certificate: Uint8List.fromList(cc),
              privateKey: Uint8List.fromList(ck),
            ),
          ],
          pins: book,
        ),
        book,
      );
    }

    test('first use records the key, the second connection matches', () async {
      if (!available) return markTestSkipped('openssl not found');
      final (cert, key) = await TestServer.selfSignedCertificate();
      final s = await serve(cert, key);
      final (tls, book) = await trusting(cert);
      final first = await get(s.port, tls, verify: true);
      expect(first.tls!.pin, PinStatus.recorded);
      final pin = book.lookup('127.0.0.1', s.port)!;
      expect(pin.spki, parseCertificate(Uint8List.fromList(cert)).spkiSha256);
      expect(pin.subject, contains('localhost'));
      final second = await get(s.port, tls, verify: true);
      expect(second.tls!.pin, PinStatus.matches);
    });

    test('a different key is refused before anything is sent', () async {
      if (!available) return markTestSkipped('openssl not found');
      final (cert, key) = await TestServer.selfSignedCertificate();
      final s = await serve(cert, key);
      final (tls, _) = await trusting(
        cert,
        pins: [
          PinEntry(
            host: '127.0.0.1',
            port: s.port,
            spki: 'AA:BB',
            manual: true,
          ),
        ],
      );
      await expectLater(
        get(s.port, tls, verify: true),
        throwsA(
          isA<PinMismatchError>().having(
            (e) => e.message,
            'm',
            contains('AA:BB'),
          ),
        ),
      );
    });

    test(
      'an SSE stream records the key, then refuses a different one',
      () async {
        if (!available) return markTestSkipped('openssl not found');
        final (cert, key) = await TestServer.selfSignedCertificate();
        final s = await serve(cert, key);
        final url = Uri.parse('https://127.0.0.1:${s.port}/');
        final (tls, book) = await trusting(cert);
        final ok = await connectSse(
          url,
          settings: HttpSettings(verifyTls: true, tls: tls),
        );
        await ok.close();
        expect(book.lookup('127.0.0.1', s.port), isNotNull);
        final (bad, _) = await trusting(
          cert,
          pins: [
            PinEntry(
              host: '127.0.0.1',
              port: s.port,
              spki: 'AA:BB',
              manual: true,
            ),
          ],
        );
        await expectLater(
          connectSse(url, settings: HttpSettings(verifyTls: true, tls: bad)),
          throwsA(isA<PinMismatchError>()),
        );
        await expectLater(
          connectWebSocket(
            Uri.parse('wss://127.0.0.1:${s.port}/'),
            settings: HttpSettings(verifyTls: true, tls: bad),
          ),
          throwsA(isA<PinMismatchError>()),
        );
      },
    );

    test('the same key in a renewed certificate passes', () async {
      if (!available) return markTestSkipped('openssl not found');
      final (cert, key) = await TestServer.selfSignedCertificate();
      File('${dir.path}/k.pem').writeAsBytesSync(key);
      final ok = await openssl([
        'req',
        '-x509',
        '-new',
        '-key',
        '${dir.path}/k.pem',
        '-out',
        '${dir.path}/c2.pem', //
        '-days', '30', '-subj', '/CN=localhost',
        '-addext', 'subjectAltName=DNS:localhost,IP:127.0.0.1',
        '-addext',
        'keyUsage=critical,digitalSignature,keyEncipherment,keyCertSign',
        '-addext', 'extendedKeyUsage=serverAuth,clientAuth',
      ]);
      if (!ok) {
        return markTestSkipped('openssl cannot make a second certificate');
      }
      final renewed = File('${dir.path}/c2.pem').readAsBytesSync();
      expect(
        parseCertificate(Uint8List.fromList(renewed)).sha256,
        isNot(parseCertificate(Uint8List.fromList(cert)).sha256),
      );
      final s = await serve(renewed, key);
      final old = parseCertificate(Uint8List.fromList(cert));
      final (tls, book) = await trusting(
        renewed,
        pins: [PinEntry.firstUse('127.0.0.1', s.port, old, DateTime.utc(2026))],
      );
      final r = await get(s.port, tls, verify: true);
      expect(r.tls!.pin, PinStatus.matches);
      // The recorded certificate details moved on to the new certificate.
      expect(book.lookup('127.0.0.1', s.port)!.leaf, r.tls!.fingerprint);
    });

    test('with verification off nothing is recorded or checked', () async {
      if (!available) return markTestSkipped('openssl not found');
      final (cert, key) = await TestServer.selfSignedCertificate();
      final s = await serve(cert, key);
      final (tls, book) = await trusting(
        cert,
        pins: [
          PinEntry(
            host: '127.0.0.1',
            port: s.port,
            spki: 'AA:BB',
            manual: true,
          ),
        ],
      );
      final r = await get(s.port, tls);
      expect(r.tls!.pin, PinStatus.unverified);
      final (tls2, book2) = await trusting(cert);
      await get(s.port, tls2);
      expect(book.entries.single.spki, 'AA:BB');
      expect(book2.entries, isEmpty);
    });

    test(
      'a host without a client certificate is not pinned by default',
      () async {
        if (!available) return markTestSkipped('openssl not found');
        final (cert, key) = await TestServer.selfSignedCertificate();
        final s = await serve(cert, key);
        final book = PinBook();
        final r = await get(
          s.port,
          TlsConfig(caCertificates: [Uint8List.fromList(cert)], pins: book),
          verify: true,
        );
        expect(r.tls!.pin, PinStatus.notApplicable);
        expect(book.entries, isEmpty);
      },
    );

    test('a test connection compares but records nothing', () async {
      if (!available) return markTestSkipped('openssl not found');
      final (cert, key) = await TestServer.selfSignedCertificate();
      final s = await serve(cert, key);
      final (tls, book) = await trusting(cert);
      final p = await probeTls(
        Uri.parse('https://127.0.0.1:${s.port}/'),
        tls: tls,
      );
      expect(p.pin.status, PinStatus.recorded);
      expect(book.entries, isEmpty);
    });

    test('the minimum TLS version is enforced', () async {
      if (!available) return markTestSkipped('openssl not found');
      // `openssl s_server` serves one connection at a time and the readiness
      // check below hangs it on the Windows runner (30 s timeout in CI).
      if (Platform.isWindows) return markTestSkipped('s_server on Windows');
      final (cert, key) = await TestServer.selfSignedCertificate();
      File('${dir.path}/c.pem').writeAsBytesSync(cert);
      File('${dir.path}/k.pem').writeAsBytesSync(key);
      // A server that speaks TLS 1.2 only.
      final tmp = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
      final port = tmp.port;
      await tmp.close();
      final Process p;
      try {
        p = await Process.start('openssl', [
          's_server', '-accept', '$port', '-cert', '${dir.path}/c.pem', //
          '-key', '${dir.path}/k.pem', '-tls1_2', '-quiet',
        ]);
      } on ProcessException {
        return markTestSkipped('openssl s_server not available');
      }
      addTearDown(p.kill);
      unawaited(p.stdout.drain<void>());
      unawaited(p.stderr.drain<void>());
      // Wait until it listens.
      for (var i = 0; i < 40; i++) {
        try {
          (await Socket.connect('127.0.0.1', port)).destroy();
          break;
        } on SocketException {
          await Future<void>.delayed(const Duration(milliseconds: 100));
        }
      }
      TlsConfig tls(TlsVersion? min) => TlsConfig(
        caCertificates: [Uint8List.fromList(cert)],
        minimumVersion: min,
      );
      final url = Uri.parse('https://127.0.0.1:$port/');
      // A handshake is enough: no request is needed to see the version.
      final ok = await probeTls(url, tls: tls(TlsVersion.v12));
      expect(ok.trusted, isTrue);
      await expectLater(
        probeTls(url, tls: tls(TlsVersion.v13)),
        throwsA(isA<TlsProbeError>()),
      );
    });
  });
}
