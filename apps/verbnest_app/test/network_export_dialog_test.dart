import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:verbnest_app/src/settings_page.dart';
import 'package:verbnest_app/src/state/file_port.dart';
import 'package:verbnest_app/src/state/network_state.dart';
import 'package:verbnest_app/src/state/session.dart';
import 'package:verbnest_app/src/widgets/network_export_dialog.dart';
import 'package:verbnest_runner/verbnest_runner.dart';

class _Files implements FilePort {
  String? name;
  Uint8List? bytes;

  @override
  Future<PickedFile?> pick() async => null;

  @override
  Future<bool> save(String n, Uint8List b, {String? mime}) async {
    name = n;
    bytes = b;
    return true;
  }

  @override
  bool get savesBySharing => false;
}

/// Settings > Network > Export for the command line (FR-HTTP-013c).
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
        networkExportRoundsProvider.overrideWithValue(10000),
      ],
    );
    addTearDown(c.dispose);
    c
        .read(networkProvider.notifier)
        .set(
          NetworkConfig(
            proxyEnabled: true,
            proxyHost: 'proxy.test',
            proxyPassword: 'proxy-secret',
            clientCerts: [
              ClientCertEntry(
                id: 'a',
                pattern: 'api.test',
                name: 'API',
                certificate: Uint8List.fromList(
                  utf8.encode('CERTIFICATE-BYTES'),
                ),
                privateKey: Uint8List.fromList(utf8.encode('KEY-BYTES')),
                passphrase: 'key-pass',
              ),
            ],
          ),
        );
    await t.pumpWidget(
      UncontrolledProviderScope(
        container: c,
        child: const MaterialApp(home: Scaffold(body: SettingsPage())),
      ),
    );
    await t.scrollUntilVisible(
      find.byKey(const Key('export-network')),
      200,
      scrollable: find.byType(Scrollable).first,
    );
    await t.tap(find.byKey(const Key('export-network')));
    await t.pumpAndSettle();
    return (c, files);
  }

  testWidgets('different passphrases are refused and nothing is saved', (
    t,
  ) async {
    final (_, files) = await open(t);
    await t.enterText(find.byKey(const Key('export-pass')), 'one');
    await t.enterText(find.byKey(const Key('export-pass2')), 'two');
    await t.tap(find.byKey(const Key('export-confirm')));
    await t.pumpAndSettle();
    expect(find.byKey(const Key('export-error')), findsOneWidget);
    expect(files.bytes, isNull);
    // An empty passphrase is refused too.
    await t.enterText(find.byKey(const Key('export-pass')), '');
    await t.enterText(find.byKey(const Key('export-pass2')), '');
    await t.tap(find.byKey(const Key('export-confirm')));
    await t.pumpAndSettle();
    expect(find.byKey(const Key('export-error')), findsOneWidget);
    expect(files.bytes, isNull);
  });

  testWidgets('the saved file opens with the passphrase and nothing else', (
    t,
  ) async {
    final (_, files) = await open(t);
    await t.enterText(find.byKey(const Key('export-pass')), 'open sesame');
    await t.enterText(find.byKey(const Key('export-pass2')), 'open sesame');
    await t.tap(find.byKey(const Key('export-confirm')));
    // The work runs in another isolate, which fake time does not wait for.
    await t.runAsync(() async {
      for (var i = 0; i < 100 && files.bytes == null; i++) {
        await Future<void>.delayed(const Duration(milliseconds: 100));
      }
    });
    await t.pumpAndSettle();
    expect(files.name, 'verbnest-network.json');
    final text = utf8.decode(files.bytes!);
    for (final secret in [
      'CERTIFICATE-BYTES',
      'KEY-BYTES',
      'key-pass',
      'proxy-secret',
      'open sesame',
    ]) {
      expect(text, isNot(contains(secret)));
    }
    final back = await t.runAsync(
      () => NetworkExport.decrypt(files.bytes!, 'open sesame'),
    );
    expect(back!.proxyPassword, 'proxy-secret');
    expect(utf8.decode(back.clientCerts.single.privateKey!), 'KEY-BYTES');
    expect(back.clientCerts.single.passphrase, 'key-pass');
    // The dialog closed.
    expect(find.byKey(const Key('export-pass')), findsNothing);
  });
}
