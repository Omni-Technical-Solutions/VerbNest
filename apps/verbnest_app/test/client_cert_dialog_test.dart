import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:verbnest_app/src/settings_page.dart';
import 'package:verbnest_app/src/state/file_port.dart';
import 'package:verbnest_app/src/state/network_state.dart';
import 'package:verbnest_app/src/state/session.dart';
import 'package:verbnest_app/src/state/settings_state.dart';
import 'package:verbnest_http/verbnest_http.dart';

/// The client certificate dialog loads the files the way the engine will, so
/// a wrong passphrase or a key that does not match shows when it is chosen and
/// not at the first request (FR-HTTP-013a).
class _Files implements FilePort {
  PickedFile? next;

  @override
  Future<PickedFile?> pick() async => next;

  @override
  Future<bool> save(String n, Uint8List b, {String? mime}) async => true;

  @override
  bool get savesBySharing => false;
}

class _Material {
  _Material(this.cert, this.key, this.otherKey, this.p12);

  final Uint8List cert;
  final Uint8List key;
  final Uint8List otherKey;
  final Uint8List p12;
}

Future<_Material?> _make() async {
  final dir = await Directory.systemTemp.createTemp('verbnest-dialog');
  try {
    Future<bool> run(List<String> a) async {
      try {
        return (await Process.run('openssl', a)).exitCode == 0;
      } on ProcessException {
        return false;
      }
    }

    String p(String n) => '${dir.path}/$n';
    final ok =
        await run([
          'req', '-x509', '-newkey', 'rsa:2048', '-nodes', //
          '-keyout', p('k.pem'), '-out', p('c.pem'), //
          '-days', '90', '-subj', '/CN=dialog-client',
        ]) &&
        await run([
          'req', '-x509', '-newkey', 'rsa:2048', '-nodes', //
          '-keyout', p('o.pem'), '-out', p('oc.pem'), //
          '-days', '90', '-subj', '/CN=other',
        ]) &&
        await run([
          'pkcs12', '-export', '-in', p('c.pem'), '-inkey', p('k.pem'), //
          '-out', p('b.p12'), '-passout', 'pass:hunter2',
        ]);
    if (!ok) return null;
    Uint8List r(String n) => File(p(n)).readAsBytesSync();
    return _Material(r('c.pem'), r('k.pem'), r('o.pem'), r('b.p12'));
  } finally {
    await dir.delete(recursive: true);
  }
}

void main() {
  Future<(ProviderContainer, _Files)> open(WidgetTester t) async {
    t.view.physicalSize = const Size(1000, 1800);
    t.view.devicePixelRatio = 1;
    addTearDown(t.view.reset);
    final s = WorkspaceSession.memory();
    addTearDown(s.close);
    final files = _Files();
    final c = ProviderContainer(
      overrides: [
        sessionProvider.overrideWithValue(s),
        filePortProvider.overrideWithValue(files),
      ],
    );
    addTearDown(c.dispose);
    await t.pumpWidget(
      UncontrolledProviderScope(
        container: c,
        child: const MaterialApp(home: Scaffold(body: SettingsPage())),
      ),
    );
    final list = find.byType(Scrollable).first;
    await t.scrollUntilVisible(
      find.byKey(const Key('add-client-cert')),
      200,
      scrollable: list,
    );
    await t.tap(find.byKey(const Key('add-client-cert')));
    await t.pumpAndSettle();
    return (c, files);
  }

  Future<void> pick(
    WidgetTester t,
    _Files f,
    String key,
    String name,
    Uint8List b,
  ) async {
    f.next = PickedFile(name, b);
    await t.tap(find.byKey(Key(key)));
    await t.pumpAndSettle();
  }

  bool canSave(WidgetTester t) =>
      t.widget<FilledButton>(find.byKey(const Key('save-cert'))).onPressed !=
      null;

  testWidgets('a key of another certificate is refused with a reason', (
    t,
  ) async {
    final m = await t.runAsync(_make);
    if (m == null) return markTestSkipped('openssl not found');
    final (_, files) = await open(t);
    await pick(t, files, 'pick-cert', 'me.pem', m.cert);
    await pick(t, files, 'pick-key', 'other.key', m.otherKey);
    expect(find.byKey(const Key('cert-problem')), findsOneWidget);
    expect(find.textContaining('does not match'), findsOneWidget);
    expect(canSave(t), isFalse);
    // The right key clears it, shows the details, and allows saving.
    await pick(t, files, 'pick-key', 'me.key', m.key);
    expect(find.byKey(const Key('cert-problem')), findsNothing);
    final details = t.widget<SelectableText>(
      find.byKey(const Key('cert-details')),
    );
    expect(details.data, contains('CN=dialog-client'));
    expect(details.data, contains('RSA 2048'));
    expect(details.data, contains('SHA-256: '));
    expect(find.byKey(const Key('cert-warning-0')), findsOneWidget);
    expect(canSave(t), isTrue);
  });

  testWidgets('a combined PEM (certificate and key in one file) enables Add', (
    t,
  ) async {
    final m = await t.runAsync(_make);
    if (m == null) return markTestSkipped('openssl not found');
    final (c, files) = await open(t);
    await pick(
      t,
      files,
      'pick-cert',
      'both.pem',
      Uint8List.fromList([...m.cert, ...m.key]),
    );
    // No second file is needed: the key is taken from the same one.
    expect(find.byKey(const Key('cert-problem')), findsNothing);
    expect(
      find.textContaining('found in the certificate file'),
      findsOneWidget,
    );
    expect(canSave(t), isTrue);
    await t.tap(find.byKey(const Key('save-cert')));
    await t.pumpAndSettle();
    expect(c.read(networkProvider).clientCerts.single.privateKey, isNotNull);
  });

  testWidgets('a PEM certificate alone says why Add is off', (t) async {
    final m = await t.runAsync(_make);
    if (m == null) return markTestSkipped('openssl not found');
    final (_, files) = await open(t);
    await pick(t, files, 'pick-cert', 'me.pem', m.cert);
    expect(canSave(t), isFalse);
    expect(find.textContaining('choose its private key'), findsOneWidget);
    await pick(t, files, 'pick-key', 'me.key', m.key);
    expect(find.byKey(const Key('cert-problem')), findsNothing);
    expect(canSave(t), isTrue);
    // Choosing another certificate afterwards asks for its key again only
    // when the new file has none.
    await pick(t, files, 'pick-cert', 'other.pem', m.cert);
    expect(canSave(t), isTrue);
  });

  // `openssl pkcs12 -nodes` and some CAs write text before the first block.
  // The key row used to depend on a file starting with the block within 80
  // bytes, while the message asking for the key did not.
  Uint8List headed(Uint8List pem, int headerBytes) {
    final text = StringBuffer('Bag Attributes\n');
    while (text.length < headerBytes) {
      text.write('subject=/CN=dialog-client/O=Example Organisation\n');
    }
    return Uint8List.fromList([...text.toString().codeUnits, ...pem]);
  }

  for (final header in [94, 300]) {
    testWidgets('a PEM certificate with $header bytes of text first still '
        'offers its private key', (t) async {
      final m = await t.runAsync(_make);
      if (m == null) return markTestSkipped('openssl not found');
      final (c, files) = await open(t);
      await pick(t, files, 'pick-cert', 'me.pem', headed(m.cert, header));
      expect(find.textContaining('choose its private key'), findsOneWidget);
      expect(find.byKey(const Key('pick-key')), findsOneWidget);
      expect(canSave(t), isFalse);
      await pick(t, files, 'pick-key', 'me.key', headed(m.key, header));
      expect(find.byKey(const Key('cert-problem')), findsNothing);
      expect(canSave(t), isTrue);
      await t.tap(find.byKey(const Key('save-cert')));
      await t.pumpAndSettle();
      expect(c.read(networkProvider).clientCerts.single.privateKey, isNotNull);
    });
  }

  testWidgets('a combined PEM with text first takes its key from the file', (
    t,
  ) async {
    final m = await t.runAsync(_make);
    if (m == null) return markTestSkipped('openssl not found');
    final (c, files) = await open(t);
    final both = headed(Uint8List.fromList([...m.cert, ...m.key]), 300);
    await pick(t, files, 'pick-cert', 'both.pem', both);
    expect(find.byKey(const Key('cert-problem')), findsNothing);
    expect(
      find.textContaining('found in the certificate file'),
      findsOneWidget,
    );
    expect(canSave(t), isTrue);
    await t.tap(find.byKey(const Key('save-cert')));
    await t.pumpAndSettle();
    expect(c.read(networkProvider).clientCerts.single.privateKey, isNotNull);
  });

  testWidgets('a PKCS#12 bundle checks the passphrase as it is typed', (
    t,
  ) async {
    final m = await t.runAsync(_make);
    if (m == null) return markTestSkipped('openssl not found');
    final (c, files) = await open(t);
    await pick(t, files, 'pick-cert', 'me.p12', m.p12);
    expect(find.byKey(const Key('pick-key')), findsNothing);
    expect(find.textContaining('needs a passphrase'), findsOneWidget);
    expect(canSave(t), isFalse);
    await t.enterText(find.byKey(const Key('cert-pass')), 'nope');
    await t.pump();
    expect(find.textContaining('passphrase is wrong'), findsOneWidget);
    expect(canSave(t), isFalse);
    await t.enterText(find.byKey(const Key('cert-pass')), 'hunter2');
    await t.pump();
    expect(find.byKey(const Key('cert-problem')), findsNothing);
    expect(find.textContaining('PKCS#12'), findsOneWidget);
    expect(canSave(t), isTrue);
    await t.tap(find.byKey(const Key('save-cert')));
    await t.pumpAndSettle();
    expect(c.read(networkProvider).clientCerts.single.passphrase, 'hunter2');
  });

  testWidgets('the saved certificate shows when it expires', (t) async {
    final m = await t.runAsync(_make);
    if (m == null) return markTestSkipped('openssl not found');
    final (c, files) = await open(t);
    await pick(t, files, 'pick-cert', 'me.pem', m.cert);
    await pick(t, files, 'pick-key', 'me.key', m.key);
    await t.tap(find.byKey(const Key('save-cert')));
    await t.pumpAndSettle();
    final id = c.read(networkProvider).clientCerts.single.id;
    expect(
      find.descendant(
        of: find.byKey(Key('client-cert-$id')),
        matching: find.textContaining('expires '),
      ),
      findsOneWidget,
    );
  });

  testWidgets('a file that is not a certificate cannot be saved', (t) async {
    final (_, files) = await open(t);
    await pick(
      t,
      files,
      'pick-cert',
      'junk.p12',
      Uint8List.fromList([1, 2, 3, 4]),
    );
    expect(find.textContaining('not a certificate'), findsOneWidget);
    expect(canSave(t), isFalse);
  });

  testWidgets('an entry can be switched off and on', (t) async {
    final m = await t.runAsync(_make);
    if (m == null) return markTestSkipped('openssl not found');
    final (c, files) = await open(t);
    await pick(t, files, 'pick-cert', 'me.pem', m.cert);
    await pick(t, files, 'pick-key', 'me.key', m.key);
    await t.tap(find.byKey(const Key('save-cert')));
    await t.pumpAndSettle();
    final id = c.read(networkProvider).clientCerts.single.id;
    TlsConfig tls() => c.read(httpDefaultsProvider).tls!;
    expect(tls().clientCertificateFor('api.test'), isNotNull);
    await t.tap(find.byKey(Key('cert-enabled-$id')));
    await t.pumpAndSettle();
    expect(c.read(networkProvider).clientCerts.single.enabled, isFalse);
    expect(tls().clientCertificateFor('api.test'), isNull);
    await t.tap(find.byKey(Key('cert-enabled-$id')));
    await t.pumpAndSettle();
    expect(tls().clientCertificateFor('api.test'), isNotNull);
  });

  testWidgets('editing keeps the files and changes the host and name', (
    t,
  ) async {
    final m = await t.runAsync(_make);
    if (m == null) return markTestSkipped('openssl not found');
    final (c, files) = await open(t);
    await pick(t, files, 'pick-cert', 'me.pem', m.cert);
    await pick(t, files, 'pick-key', 'me.key', m.key);
    await t.tap(find.byKey(const Key('save-cert')));
    await t.pumpAndSettle();
    final before = c.read(networkProvider).clientCerts.single;
    await t.tap(find.byKey(Key('edit-cert-${before.id}')));
    await t.pumpAndSettle();
    // The stored files are loaded again, so the details show at once.
    expect(find.byKey(const Key('cert-details')), findsOneWidget);
    expect(canSave(t), isTrue);
    await t.enterText(find.byKey(const Key('cert-host')), 'api.test:8443');
    await t.enterText(find.byKey(const Key('cert-name')), 'Staging API');
    await t.tap(find.byKey(const Key('save-cert')));
    await t.pumpAndSettle();
    final after = c.read(networkProvider).clientCerts.single;
    expect(after.id, before.id);
    expect(after.pattern, 'api.test:8443');
    expect(after.name, 'Staging API');
    expect(after.privateKey, before.privateKey);
    expect(after.certificate, before.certificate);
    expect(
      c
          .read(httpDefaultsProvider)
          .tls!
          .clientCertificateFor('api.test', port: 8443)!
          .label,
      'Staging API',
    );
    expect(
      c
          .read(httpDefaultsProvider)
          .tls!
          .clientCertificateFor('api.test', port: 443),
      isNull,
    );
  });

  testWidgets('"no client certificate" beats a broader entry', (t) async {
    final m = await t.runAsync(_make);
    if (m == null) return markTestSkipped('openssl not found');
    final (c, files) = await open(t);
    await pick(t, files, 'pick-cert', 'me.pem', m.cert);
    await pick(t, files, 'pick-key', 'me.key', m.key);
    await t.tap(find.byKey(const Key('save-cert')));
    await t.pumpAndSettle();
    await t.scrollUntilVisible(
      find.byKey(const Key('add-client-cert')),
      200,
      scrollable: find.byType(Scrollable).first,
    );
    await t.tap(find.byKey(const Key('add-client-cert')));
    await t.pumpAndSettle();
    await t.tap(find.byKey(const Key('cert-none')));
    await t.pump();
    expect(find.byKey(const Key('pick-cert')), findsNothing);
    await t.enterText(find.byKey(const Key('cert-host')), 'internal.test');
    await t.tap(find.byKey(const Key('save-cert')));
    await t.pumpAndSettle();
    final tls = c.read(httpDefaultsProvider).tls!;
    expect(c.read(networkProvider).clientCerts.length, 2);
    expect(tls.clientCertificateFor('internal.test'), isNull);
    expect(tls.clientCertificateFor('api.test'), isNotNull);
  });

  test('stored settings: old data reads as enabled, new fields round trip', () {
    final s = WorkspaceSession.memory();
    addTearDown(s.close);
    ProviderContainer open() {
      final c = ProviderContainer(
        overrides: [sessionProvider.overrideWithValue(s)],
      );
      addTearDown(c.dispose);
      return c;
    }

    final first = open();
    final cert = Uint8List.fromList([1, 2, 3]);
    first
        .read(networkProvider.notifier)
        .set(
          NetworkConfig(
            clientCerts: [
              ClientCertEntry(
                id: 'a',
                pattern: '*',
                name: 'one',
                certificate: cert,
                privateKey: Uint8List(2),
              ),
              ClientCertEntry(
                id: 'b',
                pattern: 'x.test',
                name: 'two',
                certificate: cert,
                privateKey: Uint8List(2),
                enabled: false,
              ),
              ClientCertEntry(
                id: 'c',
                pattern: 'y.test:9',
                name: 'none',
                certificate: Uint8List(0),
                none: true,
              ),
            ],
          ),
        );
    final again = open().read(networkProvider).clientCerts;
    expect(again.map((e) => e.enabled), [true, false, true]);
    expect(again.map((e) => e.none), [false, false, true]);
    expect(again[2].pattern, 'y.test:9');
    // A config written before these fields existed has neither key.
    final raw = s.local.kv(s.repo.workspaceId, 'network');
    expect(raw, isNotNull);
    expect(raw, isNot(contains('"enabled":true')));
  });
}
