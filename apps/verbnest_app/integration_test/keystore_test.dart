// The system keystore bridge on a real device (FR-HTTP-013f), macOS and Android:
// a PKCS#12 file is imported into the Keychain through the native plugin and a
// request is made with it through the loopback relay to a local mutual-TLS
// server. Certificates are made with openssl at run time; nothing is checked
// in. The identity is removed again at the end.
//
//   flutter test integration_test/keystore_test.dart -d macos
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:verbnest_app/src/state/keystore_relay.dart';
import 'package:verbnest_http/verbnest_http.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('import into the Keychain, then a request through the relay', (
    t,
  ) async {
    if (!Platform.isMacOS && !Platform.isAndroid && !Platform.isIOS) return;
    // The iOS simulator runs unsigned builds, which have no keychain
    // entitlement (SecItemAdd fails with -25303): use a signed device.
    if (Platform.isIOS &&
        Platform.environment.containsKey('SIMULATOR_DEVICE_NAME')) {
      markTestSkipped('needs a signed iOS device, not the simulator');
      return;
    }
    // The sandboxed app cannot run openssl, so scripts/keystore_macos_test.sh
    // makes throwaway certificates (valid for a day) and passes them in.
    Uint8List def(String v) => base64Decode(v);
    const p12Text = String.fromEnvironment('KS_P12');
    if (p12Text.isEmpty) {
      markTestSkipped('run it with scripts/keystore_macos_test.sh');
      return;
    }
    const tag = String.fromEnvironment('KS_TAG');
    final serverPem = def(const String.fromEnvironment('KS_SERVER_PEM'));
    final serverKey = def(const String.fromEnvironment('KS_SERVER_KEY'));
    final clientPem = def(const String.fromEnvironment('KS_CLIENT_PEM'));
    final p12 = def(p12Text);

    final relay = PlatformKeystoreRelay();
    expect(await relay.probe(), isTrue);

    // A wrong passphrase is a clear error and imports nothing.
    await expectLater(
      relay.import(p12, 'wrong', 'it'),
      throwsA(isA<KeystoreError>()),
    );

    final id = await relay.import(p12, 'it-pass', 'it-client');
    // The test removes it itself at the end; this covers an early failure.
    addTearDown(() async {
      try {
        await relay.remove(id.id);
      } on KeystoreError {
        // already gone
      }
    });
    final listed = await relay.identities();
    expect(listed.map((i) => i.id), contains(id.id));
    expect(id.label, contains('verbnest-it-$tag'));

    final server = await SecureServerSocket.bind(
      InternetAddress.loopbackIPv4,
      0,
      SecurityContext()
        ..useCertificateChainBytes(serverPem)
        ..usePrivateKeyBytes(serverKey)
        ..setTrustedCertificatesBytes(clientPem),
      requestClientCertificate: true,
      requireClientCertificate: true,
    );
    addTearDown(server.close);
    server.listen((c) {
      final buf = BytesBuilder();
      c.listen((d) async {
        buf.add(d);
        if (!latin1.decode(buf.toBytes()).contains('\r\n\r\n')) return;
        final who = c.peerCertificate?.subject ?? 'none';
        c.add(
          utf8.encode(
            'HTTP/1.1 200 OK\r\nContent-Length: ${who.length}\r\n'
            'Connection: close\r\n\r\n$who',
          ),
        );
        await c.close();
      }, onError: (Object _) {});
    }, onError: (Object _) {});

    TlsConfig config({List<Uint8List>? cas, TlsVersion? min, PinBook? pins}) =>
        TlsConfig(
          caCertificates: cas ?? [serverPem],
          clientCertificates: [ClientCertificate.keystore('127.0.0.1', id.id)],
          relay: relay,
          minimumVersion: min,
          pins: pins,
        );
    Future<HttpResponseRecord> get(TlsConfig tls, {bool verify = true}) =>
        HttpEngine().send(
          HttpRequestSpec(
            method: 'GET',
            url: Uri.parse('https://127.0.0.1:${server.port}/'),
            settings: HttpSettings(verifyTls: verify, tls: tls),
          ),
        );

    // 1. The server sees the identity's certificate; the key never left.
    final book = PinBook();
    final ok = await get(config(pins: book));
    expect(ok.status, 200);
    expect(ok.bodyText, contains('verbnest-it-$tag'));
    expect(ok.tls!.clientCertificateSent, isTrue);
    expect(ok.tls!.subject, contains('localhost'));
    expect(ok.tls!.pin, PinStatus.recorded);

    // 2. Pinned now; the same server matches.
    expect((await get(config(pins: book))).tls!.pin, PinStatus.matches);

    // 3. TLS 1.3 only works with this server.
    expect((await get(config(min: TlsVersion.v13))).status, 200);

    // 4. Not trusting the server certificate fails with a reason; with
    //    verification off it goes through.
    await expectLater(
      get(config(cas: const [])),
      throwsA(
        isA<KeystoreError>().having(
          (e) => e.message.toLowerCase(),
          'message',
          contains('trust'),
        ),
      ),
    );
    expect((await get(config(cas: const []), verify: false)).status, 200);

    // 5. The test connection (probe) shows the handshake.
    final probe = await probeTls(
      Uri.parse('https://127.0.0.1:${server.port}/'),
      tls: config(),
    );
    expect(probe.trusted, isTrue);
    expect(probe.clientCertificate!.isKeystore, isTrue);

    // 6. Once removed, the identity is reported as gone.
    await relay.remove(id.id);
    await expectLater(
      get(config()),
      throwsA(
        isA<KeystoreError>().having(
          (e) => e.message,
          'message',
          contains('not in the keystore'),
        ),
      ),
    );
  }, timeout: const Timeout(Duration(minutes: 3)));
}
