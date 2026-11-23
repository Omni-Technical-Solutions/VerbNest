import 'dart:typed_data';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:verbnest_app/src/settings_page.dart';
import 'package:verbnest_app/src/state/network_state.dart';
import 'package:verbnest_app/src/state/settings_state.dart';
import 'package:verbnest_app/src/state/session.dart';
import 'package:verbnest_app/src/widgets/pin_settings.dart';
import 'package:verbnest_http/verbnest_http.dart';

CertInfo _cert(String spki) => CertInfo(
  subject: 'CN=api.test',
  issuer: 'CN=Test CA',
  serialHex: '01',
  notBefore: DateTime.utc(2026, 1, 1),
  notAfter: DateTime.utc(2030, 1, 1),
  names: const ['api.test'],
  keyAlgorithm: 'RSA 2048',
  sha256: 'LEAF',
  spkiSha256: spki,
  selfSigned: false,
);

/// Settings > Network > Pinned servers and Test connection (FR-HTTP-013d).
void main() {
  Future<ProviderContainer> open(
    WidgetTester t, {
    NetworkConfig config = const NetworkConfig(),
    TlsProber? prober,
  }) async {
    t.view.physicalSize = const Size(1000, 2400);
    t.view.devicePixelRatio = 1;
    addTearDown(t.view.reset);
    final s = WorkspaceSession.memory();
    addTearDown(s.close);
    final c = ProviderContainer(
      overrides: [
        sessionProvider.overrideWithValue(s),
        if (prober != null) tlsProberProvider.overrideWithValue(prober),
      ],
    );
    addTearDown(c.dispose);
    c.read(networkProvider.notifier).set(config);
    await t.pumpWidget(
      UncontrolledProviderScope(
        container: c,
        child: const MaterialApp(home: Scaffold(body: SettingsPage())),
      ),
    );
    await t.scrollUntilVisible(
      find.byKey(const Key('test-connection')),
      200,
      scrollable: find.byType(Scrollable).first,
    );
    return c;
  }

  const pin = PinEntry(host: 'api.test', spki: 'AA:BB', subject: 'CN=api.test');

  testWidgets('pins are listed, switched off and forgotten', (t) async {
    final c = await open(t, config: const NetworkConfig(pins: [pin]));
    expect(find.byKey(const Key('pin-api.test:443')), findsOneWidget);
    await t.tap(find.byKey(const Key('pin-enabled-api.test:443')));
    await t.pump();
    expect(c.read(networkProvider).pins.single.enabled, isFalse);
    await t.tap(find.byKey(const Key('pin-remove-api.test:443')));
    await t.pump();
    expect(c.read(networkProvider).pins, isEmpty);
  });

  testWidgets('the pinning switch and the minimum TLS version are saved', (
    t,
  ) async {
    final c = await open(t);
    await t.tap(find.byKey(const Key('pin-by-default')));
    await t.pump();
    expect(c.read(networkProvider).pinByDefault, isFalse);
    await t.tap(find.text('1.3'));
    await t.pump();
    expect(c.read(networkProvider).minTls, TlsVersion.v13);
    await t.tap(find.text('Default'));
    await t.pump();
    expect(c.read(networkProvider).minTls, isNull);
  });

  testWidgets('first-use pins recorded by the engine are saved', (t) async {
    final c = await open(
      t,
      config: NetworkConfig(
        clientCerts: [
          ClientCertEntry(
            id: 'a',
            pattern: 'api.test',
            name: 'API',
            certificate: Uint8List.fromList([1]),
          ),
        ],
      ),
    );
    // A client certificate entry applies to the host, so pinning is in scope.
    final tls = c.read(httpDefaultsProvider).tls!;
    final r = checkPin(tls, 'api.test', 443, _cert('K1'), verified: true);
    expect(r.status, PinStatus.recorded);
    expect(c.read(networkProvider).pins.single.spki, 'K1');
  });

  testWidgets('Test connection shows the handshake and pins the server', (
    t,
  ) async {
    final c = await open(
      t,
      prober: (url, tls) async => TlsProbe(
        server: _cert('K1'),
        trusted: true,
        hostMatches: true,
        protocol: 'TLSv1.3',
        clientCertificate: null,
        clientCertificateConfigured: false,
        rejectedClientCertificate: false,
        time: const Duration(milliseconds: 12),
        pin: checkPin(
          tls,
          url.host,
          443,
          _cert('K1'),
          verified: true,
          record: false,
        ),
      ),
    );
    await t.tap(find.byKey(const Key('test-connection')));
    await t.pumpAndSettle();
    await t.enterText(find.byKey(const Key('test-url')), 'api.test');
    await t.tap(find.byKey(const Key('test-run')));
    await t.pumpAndSettle();
    expect(find.byKey(const Key('test-ok')), findsOneWidget);
    await t.tap(find.byKey(const Key('test-pin')));
    await t.pumpAndSettle();
    expect(c.read(networkProvider).pins.single.spki, 'K1');
    expect(c.read(networkProvider).pins.single.host, 'api.test');
  });

  testWidgets('Test connection reports a changed key and can trust it', (
    t,
  ) async {
    final c = await open(
      t,
      config: const NetworkConfig(pins: [pin]),
      prober: (url, tls) async => TlsProbe(
        server: _cert('NEW'),
        trusted: true,
        hostMatches: true,
        protocol: null,
        clientCertificate: null,
        clientCertificateConfigured: false,
        rejectedClientCertificate: false,
        time: const Duration(milliseconds: 5),
        pin: checkPin(
          tls,
          url.host,
          443,
          _cert('NEW'),
          verified: true,
          record: false,
        ),
      ),
    );
    await t.tap(find.byKey(const Key('test-connection')));
    await t.pumpAndSettle();
    await t.enterText(find.byKey(const Key('test-url')), 'https://api.test');
    await t.tap(find.byKey(const Key('test-run')));
    await t.pumpAndSettle();
    expect(find.byKey(const Key('test-pin-mismatch')), findsOneWidget);
    await t.tap(find.byKey(const Key('test-trust-new')));
    await t.pumpAndSettle();
    expect(c.read(networkProvider).pins.single.spki, 'NEW');
  });

  testWidgets('Test connection shows a failure', (t) async {
    await open(
      t,
      prober: (url, tls) async => throw const TlsProbeError('refused'),
    );
    await t.tap(find.byKey(const Key('test-connection')));
    await t.pumpAndSettle();
    await t.enterText(find.byKey(const Key('test-url')), 'nowhere.test');
    await t.tap(find.byKey(const Key('test-run')));
    await t.pumpAndSettle();
    expect(find.byKey(const Key('test-error')), findsOneWidget);
  });
}
