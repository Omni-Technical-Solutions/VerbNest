import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:test/test.dart';
import 'package:test_server/test_server.dart';
import 'package:verbnest_http/verbnest_http.dart';

/// Stands in for the platform: accepts plain TCP on loopback and opens real
/// TLS, with a client identity the test holds, to the server (what the native
/// relays do). The engine under test only ever sees the loopback socket.
class _DartRelay implements KeystoreRelay {
  _DartRelay(this.clientCert, this.clientKey, {this.fail});

  final List<int> clientCert;
  final List<int> clientKey;
  final String? fail;
  final requests = <RelayRequest>[];
  var closed = 0;

  @override
  bool get isSupported => true;

  @override
  Future<List<KeystoreIdentity>> identities() async => const [
    KeystoreIdentity(id: 'id1', label: 'Test identity'),
  ];

  @override
  Future<RelaySession> open(RelayRequest r) async {
    requests.add(r);
    if (fail != null) throw KeystoreError(fail!);
    final context = SecurityContext(withTrustedRoots: false);
    for (final ca in r.caCertificates) {
      context.setTrustedCertificatesBytes(ca);
    }
    context
      ..useCertificateChainBytes(clientCert)
      ..usePrivateKeyBytes(clientKey);
    final sw = Stopwatch()..start();
    final SecureSocket upstream;
    try {
      upstream = await SecureSocket.connect(
        r.host,
        r.port,
        context: context,
        onBadCertificate: r.verify ? null : (_) => true,
      );
    } on TlsException catch (e) {
      // The native relays report a failed handshake the same way.
      throw KeystoreError('TLS handshake failed: ${e.message}');
    }
    final der = upstream.peerCertificate?.der;
    final handshake = sw.elapsed;
    final server = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
    unawaited(
      server.first
          .then((inbound) {
            inbound.listen(upstream.add, onDone: upstream.close);
            upstream.listen(inbound.add, onDone: inbound.close);
          })
          .catchError((Object _) {
            upstream.destroy();
          }),
    );
    return _Session(server, der, handshake, () => closed++);
  }
}

class _Session implements RelaySession {
  _Session(
    this._server,
    this.serverCertificate,
    this.handshakeTime,
    this._onClose,
  );

  final ServerSocket _server;
  final void Function() _onClose;

  @override
  final Uint8List? serverCertificate;
  @override
  final Duration handshakeTime;
  @override
  int get port => _server.port;
  @override
  String? get protocol => 'http/1.1';
  @override
  Future<void> close() async {
    _onClose();
    await _server.close();
  }
}

/// Client certificates held by the system keystore (FR-HTTP-013f), reached
/// through [KeystoreRelay].
void main() {
  late bool available;
  setUpAll(() async => available = await TestServer.tlsAvailable);

  late SecureServerSocket server;
  late List<int> serverCert;
  late _DartRelay relay;

  setUp(() async {
    if (!available) return;
    final (cert, key) = await TestServer.selfSignedCertificate();
    final (cc, ck) = await TestServer.selfSignedCertificate(
      cn: 'keystore-client',
    );
    serverCert = cert;
    relay = _DartRelay(cc, ck);
    server = await SecureServerSocket.bind(
      InternetAddress.loopbackIPv4,
      0,
      SecurityContext()
        ..useCertificateChainBytes(cert)
        ..usePrivateKeyBytes(key)
        ..setTrustedCertificatesBytes(cc),
      requestClientCertificate: true,
      requireClientCertificate: true,
    );
    server.listen((c) {
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
  });
  tearDown(() async {
    if (available) await server.close();
  });

  Future<HttpResponseRecord> get(
    TlsConfig tls, {
    ProxyConfig? proxy,
    bool verify = true,
  }) => HttpEngine().send(
    HttpRequestSpec(
      method: 'GET',
      url: Uri.parse('https://127.0.0.1:${server.port}/'),
      settings: HttpSettings(verifyTls: verify, tls: tls, proxy: proxy),
    ),
  );

  TlsConfig config({KeystoreRelay? r, PinBook? pins}) => TlsConfig(
    caCertificates: [Uint8List.fromList(serverCert)],
    clientCertificates: [
      ClientCertificate.keystore('127.0.0.1', 'id1', label: 'Work identity'),
    ],
    relay: r,
    pins: pins,
  );

  test(
    'the request goes through the relay and the server sees the identity',
    () async {
      if (!available) return markTestSkipped('openssl not found');
      final r = await get(config(r: relay));
      expect(r.status, 200);
      expect(r.bodyText, contains('keystore-client'));
      expect(relay.requests.single.identityId, 'id1');
      expect(relay.requests.single.host, '127.0.0.1');
      expect(relay.requests.single.caCertificates, isNotEmpty);
      final tls = r.tls!;
      expect(tls.clientCertificateSent, isTrue);
      expect(tls.clientCertificateLabel, 'Work identity');
      expect(tls.subject, contains('CN=localhost'));
      expect(tls.spkiFingerprint, isNotNull);
    },
  );

  test(
    'without a relay the error says the keystore is not available here',
    () async {
      if (!available) return markTestSkipped('openssl not found');
      await expectLater(
        get(config()),
        throwsA(
          isA<KeystoreError>().having(
            (e) => e.message,
            'message',
            contains('system keystore'),
          ),
        ),
      );
    },
  );

  test('a relay failure is reported as it is', () async {
    if (!available) return markTestSkipped('openssl not found');
    final bad = _DartRelay([], [], fail: 'The identity is locked.');
    await expectLater(
      get(config(r: bad)),
      throwsA(
        isA<KeystoreError>().having(
          (e) => e.message,
          'm',
          'The identity is locked.',
        ),
      ),
    );
  });

  test('a proxy is refused with a reason, before anything connects', () async {
    if (!available) return markTestSkipped('openssl not found');
    await expectLater(
      get(
        config(r: relay),
        proxy: const ProxyConfig(
          kind: ProxyKind.http,
          host: '127.0.0.1',
          port: 9,
        ),
      ),
      throwsA(
        isA<KeystoreError>().having((e) => e.message, 'm', contains('proxy')),
      ),
    );
    expect(relay.requests, isEmpty);
  });

  test(
    'the server key is pinned on first use and a change is refused',
    () async {
      if (!available) return markTestSkipped('openssl not found');
      final book = PinBook();
      final first = await get(config(r: relay, pins: book));
      expect(first.tls!.pin, PinStatus.recorded);
      expect(book.entries.single.host, '127.0.0.1');
      // The same server again matches.
      final again = await get(config(r: relay, pins: book));
      expect(again.tls!.pin, PinStatus.matches);
      // Another key behind the same host is refused and the relay is closed.
      book.put(book.entries.single.copyWith(spki: '00:' * 31 + '00'));
      final before = relay.closed;
      await expectLater(
        get(config(r: relay, pins: book)),
        throwsA(isA<PinMismatchError>()),
      );
      expect(relay.closed, before + 1);
    },
  );

  test(
    'an entry that is switched off or set to none does not use the relay',
    () async {
      if (!available) return markTestSkipped('openssl not found');
      final off = TlsConfig(
        caCertificates: [Uint8List.fromList(serverCert)],
        clientCertificates: [
          ClientCertificate.keystore('127.0.0.1', 'id1', enabled: false),
        ],
        relay: relay,
      );
      // No client certificate is sent, so the mutual-TLS server turns it down.
      await expectLater(get(off), throwsA(anything));
      expect(relay.requests, isEmpty);
    },
  );

  test('keystore entries never load into a SecurityContext', () {
    final tls = config();
    expect(tls.clientCertificateFor('127.0.0.1')!.isKeystore, isTrue);
    expect(tls.contextFor('127.0.0.1'), isA<SecurityContext>());
  });

  test('probeTls reaches a keystore host through the relay', () async {
    if (!available) return markTestSkipped('openssl not found');
    final p = await probeTls(
      Uri.parse('https://127.0.0.1:${server.port}/'),
      tls: config(r: relay),
    );
    expect(p.trusted, isTrue);
    expect(p.clientCertificate!.isKeystore, isTrue);
    expect(p.rejectedClientCertificate, isFalse);
    expect(p.server.subject, contains('CN=localhost'));
    expect(relay.closed, 1);
    // Without the CA the certificate is still shown, as untrusted.
    final untrusted = await probeTls(
      Uri.parse('https://127.0.0.1:${server.port}/'),
      tls: TlsConfig(
        clientCertificates: [ClientCertificate.keystore('*', 'id1')],
        relay: relay,
      ),
    );
    expect(untrusted.trusted, isFalse);
    // No relay: a probe error that says why.
    await expectLater(
      probeTls(Uri.parse('https://127.0.0.1:${server.port}/'), tls: config()),
      throwsA(isA<TlsProbeError>()),
    );
  });

  test('KeystoreIdentity survives JSON', () {
    final i = KeystoreIdentity(
      id: 'ab',
      label: 'Work',
      subject: 'CN=me',
      issuer: 'CN=CA',
      notAfter: DateTime.utc(2030),
      sha256: 'AA:BB',
    );
    final back = KeystoreIdentity.fromJson(i.toJson());
    expect(back.id, 'ab');
    expect(back.label, 'Work');
    expect(back.notAfter, DateTime.utc(2030));
  });
}
