import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:verbnest_app/src/settings_page.dart';
import 'package:verbnest_app/src/state/file_port.dart';
import 'package:verbnest_app/src/state/network_state.dart';
import 'package:verbnest_app/src/state/session.dart';

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
}
