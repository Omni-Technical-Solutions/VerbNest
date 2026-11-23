import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:verbnest_app/src/settings_page.dart';
import 'package:verbnest_app/src/state/file_port.dart';
import 'package:verbnest_app/src/state/keystore_relay.dart';
import 'package:verbnest_app/src/state/network_state.dart';
import 'package:verbnest_app/src/state/settings_state.dart';
import 'package:verbnest_app/src/state/session.dart';
import 'package:verbnest_http/verbnest_http.dart';

class _Files implements FilePort {
  @override
  Future<PickedFile?> pick() async =>
      PickedFile('work.p12', Uint8List.fromList([1, 2, 3]));
  @override
  Future<bool> save(String n, Uint8List b, {String? mime}) async => true;
  @override
  bool get savesBySharing => false;
}

/// Client certificates from the system keystore (FR-HTTP-013f), with the
/// native side replaced by a mock of the platform channel.
void main() {
  final calls = <MethodCall>[];
  var supported = true;
  var identities = <Map<String, Object?>>[
    {'id': 'AA:BB', 'label': 'Work identity', 'subject': 'CN=me'},
    {'id': 'CC:DD', 'label': 'Lab identity'},
  ];

  setUp(() {
    calls.clear();
    supported = true;
    identities = [
      {'id': 'AA:BB', 'label': 'Work identity', 'subject': 'CN=me'},
      {'id': 'CC:DD', 'label': 'Lab identity'},
    ];
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(const MethodChannel(keystoreChannelName), (
          call,
        ) async {
          calls.add(call);
          switch (call.method) {
            case 'supported':
              return supported;
            case 'identities':
              return identities;
            case 'import':
              if ((call.arguments! as Map<Object?, Object?>)['passphrase'] ==
                  'bad') {
                throw PlatformException(
                  code: 'import',
                  message: 'wrong passphrase',
                );
              }
              final i = {'id': 'EE:FF', 'label': 'work.p12'};
              identities = [...identities, i];
              return i;
            case 'choose':
              return {'id': 'kc:work', 'label': 'Installed credential'};
            case 'close':
              return null;
          }
          return null;
        });
  });
  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel(keystoreChannelName),
          null,
        );
  });

  Future<ProviderContainer> open(WidgetTester t) async {
    t.view.physicalSize = const Size(1000, 2400);
    t.view.devicePixelRatio = 1;
    addTearDown(t.view.reset);
    final s = WorkspaceSession.memory();
    addTearDown(s.close);
    final c = ProviderContainer(
      overrides: [
        sessionProvider.overrideWithValue(s),
        filePortProvider.overrideWithValue(_Files()),
      ],
    );
    addTearDown(c.dispose);
    await t.pumpWidget(
      UncontrolledProviderScope(
        container: c,
        child: const MaterialApp(home: Scaffold(body: SettingsPage())),
      ),
    );
    await t.pumpAndSettle();
    return c;
  }

  Future<void> reveal(WidgetTester t, Key k) async {
    await t.scrollUntilVisible(
      find.byKey(k),
      200,
      scrollable: find.byType(Scrollable).first,
    );
    await t.ensureVisible(find.byKey(k));
    await t.pumpAndSettle();
  }

  testWidgets('the button is there only when the platform has a keystore', (
    t,
  ) async {
    supported = false;
    await open(t);
    await reveal(t, const Key('add-client-cert'));
    expect(find.byKey(const Key('add-keystore-cert')), findsNothing);
  });

  testWidgets('an identity is chosen, given hosts and saved by id only', (
    t,
  ) async {
    final c = await open(t);
    await reveal(t, const Key('add-keystore-cert'));
    await t.tap(find.byKey(const Key('add-keystore-cert')));
    await t.pumpAndSettle();
    expect(find.text('Work identity'), findsOneWidget);
    expect(find.text('Lab identity'), findsOneWidget);
    await t.tap(find.byKey(const Key('ks-identity-CC:DD')));
    await t.enterText(find.byKey(const Key('ks-host')), 'corp.test');
    await t.pump();
    await t.tap(find.byKey(const Key('ks-save')));
    await t.pumpAndSettle();
    final e = c.read(networkProvider).clientCerts.single;
    expect(e.keystoreId, 'CC:DD');
    expect(e.pattern, 'corp.test');
    expect(e.name, 'Lab identity');
    expect(e.certificate, isEmpty);
    expect(e.privateKey, isNull);
    // The engine's config names the identity and carries the relay.
    final tls = c.read(httpDefaultsProvider).tls!;
    expect(tls.relay, isNotNull);
    expect(tls.clientCertificateFor('corp.test')!.keystoreId, 'CC:DD');
    // The list shows it as a keystore entry.
    await reveal(t, Key('client-cert-${e.id}'));
    expect(find.textContaining('In the system keystore'), findsOneWidget);
  });

  testWidgets('Save stays off until an identity is chosen', (t) async {
    await open(t);
    await reveal(t, const Key('add-keystore-cert'));
    await t.tap(find.byKey(const Key('add-keystore-cert')));
    await t.pumpAndSettle();
    final save = t.widget<FilledButton>(find.byKey(const Key('ks-save')));
    expect(save.onPressed, isNull);
  });

  testWidgets('importing a PKCS#12 file adds it to the list, chosen', (
    t,
  ) async {
    await open(t);
    await reveal(t, const Key('add-keystore-cert'));
    await t.tap(find.byKey(const Key('add-keystore-cert')));
    await t.pumpAndSettle();
    await t.enterText(find.byKey(const Key('ks-import-pass')), 'secret');
    await t.tap(find.byKey(const Key('ks-import')));
    await t.pumpAndSettle();
    expect(find.byKey(const Key('ks-identity-EE:FF')), findsOneWidget);
    final imported = calls.firstWhere((c) => c.method == 'import');
    expect((imported.arguments! as Map<Object?, Object?>)['label'], 'work.p12');
    expect(
      (imported.arguments! as Map<Object?, Object?>)['passphrase'],
      'secret',
    );
    expect(
      t.widget<FilledButton>(find.byKey(const Key('ks-save'))).onPressed,
      isNotNull,
    );
  });

  testWidgets('a failed import shows the reason', (t) async {
    await open(t);
    await reveal(t, const Key('add-keystore-cert'));
    await t.tap(find.byKey(const Key('add-keystore-cert')));
    await t.pumpAndSettle();
    await t.enterText(find.byKey(const Key('ks-import-pass')), 'bad');
    await t.tap(find.byKey(const Key('ks-import')));
    await t.pumpAndSettle();
    expect(find.textContaining('wrong passphrase'), findsOneWidget);
  });

  testWidgets('on Android the system chooser adds a credential to the list', (
    t,
  ) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    addTearDown(() => debugDefaultTargetPlatformOverride = null);
    final c = await open(t);
    await reveal(t, const Key('add-keystore-cert'));
    await t.tap(find.byKey(const Key('add-keystore-cert')));
    await t.pumpAndSettle();
    await t.tap(find.byKey(const Key('ks-choose')));
    await t.pumpAndSettle();
    expect(find.byKey(const Key('ks-identity-kc:work')), findsOneWidget);
    await t.tap(find.byKey(const Key('ks-save')));
    await t.pumpAndSettle();
    expect(c.read(networkProvider).clientCerts.single.keystoreId, 'kc:work');
  });

  testWidgets('no identities says what to do', (t) async {
    identities = [];
    await open(t);
    await reveal(t, const Key('add-keystore-cert'));
    await t.tap(find.byKey(const Key('add-keystore-cert')));
    await t.pumpAndSettle();
    expect(find.byKey(const Key('ks-none')), findsOneWidget);
  });

  test('the channel client turns an open() answer into a session', () async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(const MethodChannel(keystoreChannelName), (
          call,
        ) async {
          calls.add(call);
          if (call.method == 'open') {
            return {
              'session': 's1',
              'port': 4242,
              'certificate': Uint8List.fromList([9, 9]),
              'protocol': 'h2',
              'handshakeMs': 12,
            };
          }
          return null;
        });
    final r = PlatformKeystoreRelay();
    final s = await r.open(
      const RelayRequest(
        host: 'a.test',
        port: 443,
        identityId: 'AA',
        minimumVersion: TlsVersion.v13,
        verify: false,
      ),
    );
    expect(s.port, 4242);
    expect(s.protocol, 'h2');
    expect(s.serverCertificate, [9, 9]);
    expect(s.handshakeTime, const Duration(milliseconds: 12));
    final args = calls.last.arguments! as Map<Object?, Object?>;
    expect(args['host'], 'a.test');
    expect(args['identity'], 'AA');
    expect(args['minVersion'], '1.3');
    expect(args['verify'], isFalse);
    await s.close();
    await s.close(); // once only
    expect(calls.where((c) => c.method == 'close'), hasLength(1));
  });
}
