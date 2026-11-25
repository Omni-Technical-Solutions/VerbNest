import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:verbnest_app/src/state/file_port.dart';
import 'package:verbnest_app/src/state/network_state.dart';
import 'package:verbnest_app/src/state/session.dart';
import 'package:verbnest_app/src/widgets/request_editor/tls_certificates_section.dart';

/// The Headers tab adds certificates in place and says which one applies
/// (plan `docs/spec/certificate-upload-plan.md`, phase N).
class _Files implements FilePort {
  PickedFile? next;

  @override
  Future<PickedFile?> pick() async => next;

  @override
  Future<bool> save(String n, Uint8List b, {String? mime}) async => true;

  @override
  bool get savesBySharing => false;
}

Future<Uint8List?> _cert() async {
  final dir = await Directory.systemTemp.createTemp('verbnest-tls-section');
  try {
    final r = await Process.run('openssl', [
      'req', '-x509', '-newkey', 'rsa:2048', '-nodes', //
      '-keyout', '${dir.path}/k.pem', '-out', '${dir.path}/c.pem',
      '-days', '90', '-subj', '/CN=section-ca',
    ]);
    return r.exitCode == 0 ? File('${dir.path}/c.pem').readAsBytesSync() : null;
  } on ProcessException {
    return null;
  } finally {
    dir.deleteSync(recursive: true);
  }
}

void main() {
  test('the target comes from the URL', () {
    final a = TlsTarget.parse('https://api.test:8443/x?y=1');
    expect((a.host, a.port, a.secure), ('api.test', 8443, true));
    expect(a.pattern, 'api.test:8443');
    expect(TlsTarget.parse('wss://a.test/s').pattern, 'a.test');
    expect(TlsTarget.parse('http://a.test/').secure, isFalse);
    expect(TlsTarget.parse('a.test/path').secure, isTrue);
    final v = TlsTarget.parse('https://{{host}}/x');
    expect((v.host, v.variable, v.pattern), (null, true, '*'));
    expect(TlsTarget.parse('').host, isNull);
  });

  Future<(ProviderContainer, _Files)> open(WidgetTester t, String url) async {
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
        child: MaterialApp(
          home: Scaffold(body: TlsCertificatesSection(url: url)),
        ),
      ),
    );
    await t.tap(find.byKey(const Key('tls-certificates')));
    await t.pumpAndSettle();
    return (c, files);
  }

  String status(WidgetTester t) =>
      t.widget<Text>(find.byKey(const Key('tls-status'))).data!;

  testWidgets('it says what applies to the host and adds a none entry', (
    t,
  ) async {
    final (c, _) = await open(t, 'https://api.test/x');
    expect(status(t), 'No client certificate for api.test.');
    expect(find.text('No trusted CAs added'), findsOneWidget);
    await t.tap(find.byKey(const Key('tls-no-cert')));
    await t.pumpAndSettle();
    final entry = c.read(networkProvider).clientCerts.single;
    expect((entry.none, entry.pattern), (true, 'api.test'));
    expect(status(t), contains('No client certificate is sent to api.test'));
  });

  testWidgets('the client certificate dialog opens with the host filled', (
    t,
  ) async {
    await open(t, 'https://api.test:8443/');
    await t.tap(find.byKey(const Key('tls-add-cert')));
    await t.pumpAndSettle();
    expect(find.byKey(const Key('save-cert')), findsOneWidget);
    expect(find.widgetWithText(TextField, 'api.test:8443'), findsOneWidget);
  });

  testWidgets('a CA is validated: a bad file is refused, a real one added', (
    t,
  ) async {
    final pem = await t.runAsync(_cert);
    final (c, files) = await open(t, 'https://api.test/');
    files.next = PickedFile('notes.txt', Uint8List.fromList([104, 105]));
    await t.tap(find.byKey(const Key('tls-add-ca')));
    await t.pumpAndSettle();
    expect(find.textContaining('notes.txt'), findsOneWidget);
    expect(c.read(networkProvider).cas, isEmpty);
    await t.pump(const Duration(seconds: 6));
    if (pem == null) return markTestSkipped('openssl not found');
    files.next = PickedFile('ca.pem', pem);
    await t.tap(find.byKey(const Key('tls-add-ca')));
    await t.pumpAndSettle();
    expect(find.textContaining('CN=section-ca'), findsOneWidget);
    expect(c.read(networkProvider).cas.single.name, 'ca.pem');
    expect(find.text('1 trusted CA added'), findsOneWidget);
  });

  testWidgets('http and variable hosts are handled', (t) async {
    await open(t, 'http://api.test/');
    expect(status(t), contains('https:// and wss://'));
    expect(find.byKey(const Key('tls-add-cert')), findsNothing);
  });

  testWidgets('a variable host adds for all hosts', (t) async {
    final (c, _) = await open(t, 'https://{{host}}/');
    expect(status(t), contains('variable'));
    await t.tap(find.byKey(const Key('tls-no-cert')));
    await t.pumpAndSettle();
    expect(c.read(networkProvider).clientCerts.single.pattern, '*');
    expect(find.byKey(const Key('tls-test')), findsNothing);
  });
}
