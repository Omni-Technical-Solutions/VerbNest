import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:postit_app/src/settings_page.dart';
import 'package:postit_app/src/state/file_port.dart';
import 'package:postit_app/src/state/network_state.dart';
import 'package:postit_app/src/state/session.dart';
import 'package:postit_app/src/state/settings_state.dart';
import 'package:postit_app/src/widgets/cookie_manager.dart';
import 'package:postit_core/postit_core.dart';
import 'package:postit_http/postit_http.dart';

class OneFile implements FilePort {
  OneFile(this.file);

  PickedFile? file;

  @override
  Future<PickedFile?> pick() async => file;

  @override
  Future<bool> save(String n, Uint8List b, {String? mime}) async => true;

  @override
  bool get savesBySharing => false;
}

Uint8List pem(String label) => Uint8List.fromList(
  '-----BEGIN $label-----\nAAAA\n-----END $label-----\n'.codeUnits,
);

ProviderContainer container(WorkspaceSession s, [FilePort? files]) {
  final c = ProviderContainer(
    overrides: [
      sessionProvider.overrideWithValue(s),
      if (files != null) filePortProvider.overrideWithValue(files),
    ],
  );
  addTearDown(c.dispose);
  return c;
}

void main() {
  test('network settings persist, keep secrets apart and reach defaults', () {
    final s = WorkspaceSession.memory();
    addTearDown(s.close);
    final c = container(s);
    c.read(networkProvider.notifier)
      ..update(
        (x) => x.copyWith(
          proxyEnabled: true,
          proxyKind: ProxyKind.socks5,
          proxyHost: 'p.test',
          proxyPort: 1080,
          proxyUser: 'ann',
          proxyPassword: 'pw',
          bypass: 'localhost, *.internal',
          useSystemProxy: true,
        ),
      )
      ..addClientCert(
        pattern: 'api.test',
        name: 'me.p12',
        certificate: pem('X'),
        passphrase: 'secret',
      );

    final d = c.read(httpDefaultsProvider);
    expect(d.proxy!.kind, ProxyKind.socks5);
    expect(d.proxy!.host, 'p.test');
    expect(d.proxy!.bypass, ['localhost', '*.internal']);
    expect(d.useSystemProxy, isTrue);
    expect(d.tls!.clientCertificates.single.hostPattern, 'api.test');

    // The password and passphrase are not in the plain kv entry.
    final raw = s.local.kv(s.repo.workspaceId, 'network')!;
    expect(raw, isNot(contains('pw"')));
    expect(raw, isNot(contains('secret')));

    // A second container over the same session reads it all back.
    final again = container(s).read(networkProvider);
    expect(again.proxyPassword, 'pw');
    expect(again.clientCerts.single.passphrase, 'secret');
    expect(again.proxy!.username, 'ann');

    // Editing a default keeps the network parts.
    c.read(httpDefaultsProvider.notifier).update(verifyTls: false);
    expect(c.read(httpDefaultsProvider).proxy, isNotNull);
  });

  test('adding a CA checks that the file looks like a certificate', () async {
    final s = WorkspaceSession.memory();
    addTearDown(s.close);
    final c = container(s);
    final n = c.read(networkProvider.notifier);
    expect(
      await n.addCa(
        OneFile(PickedFile('notes.txt', Uint8List.fromList([104, 105]))),
      ),
      contains('not a PEM or DER'),
    );
    expect(
      await n.addCa(OneFile(PickedFile('ca.pem', pem('CERTIFICATE')))),
      null,
    );
    expect(c.read(networkProvider).cas.single.name, 'ca.pem');
    expect(c.read(httpDefaultsProvider).tls!.caCertificates, hasLength(1));
    n.removeCa(0);
    expect(c.read(httpDefaultsProvider).tls, isNull);
  });

  test('the cookie jar is saved with the workspace and reloaded', () {
    final s = WorkspaceSession.memory();
    addTearDown(s.close);
    final c = container(s);
    c.read(cookiesProvider);
    c.read(cookiesProvider.notifier).jar.storeFromResponse(
      Uri.parse('https://a.test/x'),
      ['sid=1; Path=/; Max-Age=600'],
    );
    expect(c.read(cookiesProvider).single.name, 'sid');

    final again = container(s);
    expect(again.read(cookiesProvider).single.value, '1');
    again.read(cookiesProvider.notifier).clear();
    expect(container(s).read(cookiesProvider), isEmpty);
  });

  testWidgets('settings: proxy fields, certificates and cookie manager', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1000, 1800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final s = WorkspaceSession.memory();
    addTearDown(s.close);
    final files = OneFile(PickedFile('ca.pem', pem('CERTIFICATE')));
    final c = container(s, files);
    c.read(cookiesProvider);
    c
        .read(cookiesProvider.notifier)
        .jar
        .set(
          StoredCookie(
            name: 'sid',
            value: 'abc',
            domain: 'a.test',
            path: '/',
            createdAt: DateTime(2026),
          ),
        );
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: c,
        child: const MaterialApp(home: Scaffold(body: SettingsPage())),
      ),
    );
    final list = find.byType(Scrollable).first;

    await tester.scrollUntilVisible(
      find.byKey(const Key('proxy-enabled')),
      200,
      scrollable: list,
    );
    expect(find.byKey(const Key('proxy-host')), findsNothing);
    await tester.tap(find.byKey(const Key('proxy-enabled')));
    await tester.pump();
    await tester.enterText(find.byKey(const Key('proxy-host')), 'proxy.test');
    await tester.enterText(find.byKey(const Key('proxy-port')), '3128');
    await tester.pump();
    expect(c.read(httpDefaultsProvider).proxy!.host, 'proxy.test');
    expect(c.read(httpDefaultsProvider).proxy!.port, 3128);

    await tester.scrollUntilVisible(
      find.byKey(const Key('add-ca')),
      200,
      scrollable: list,
    );
    await tester.tap(find.byKey(const Key('add-ca')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('ca-0')), findsOneWidget);

    await tester.tap(find.byKey(const Key('add-client-cert')));
    await tester.pumpAndSettle();
    expect(
      tester.widget<FilledButton>(find.byKey(const Key('save-cert'))).onPressed,
      isNull,
    );
    files.file = PickedFile('me.pem', pem('CERTIFICATE'));
    await tester.tap(find.byKey(const Key('pick-cert')));
    await tester.pumpAndSettle();
    // A PEM certificate needs its key file too.
    expect(find.byKey(const Key('pick-key')), findsOneWidget);
    files.file = PickedFile('me.key', pem('PRIVATE KEY'));
    await tester.tap(find.byKey(const Key('pick-key')));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const Key('cert-host')), 'api.test');
    await tester.tap(find.byKey(const Key('save-cert')));
    await tester.pumpAndSettle();
    final cert = c.read(networkProvider).clientCerts.single;
    expect(cert.pattern, 'api.test');
    expect(cert.privateKey, isNotNull);

    await tester.scrollUntilVisible(
      find.byKey(const Key('open-cookies')),
      -200,
      scrollable: list,
    );
    await tester.tap(find.byKey(const Key('open-cookies')));
    await tester.pumpAndSettle();
    expect(find.byType(CookieManagerDialog), findsOneWidget);
    expect(find.textContaining('sid = abc'), findsOneWidget);
    await tester.tap(find.byKey(const Key('clear-cookies')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('no-cookies')), findsOneWidget);
    expect(c.read(cookiesProvider), isEmpty);
  });
}
