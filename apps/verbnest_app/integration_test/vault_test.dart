import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:verbnest_app/src/state/secure_vault.dart';
import 'package:verbnest_storage/verbnest_storage.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('platform secret store round trips a workspace blob', (_) async {
    final vault = PlatformSecretVault();
    expect(await vaultWorks(vault), isTrue);
    final s = await VaultSecretStore.load(vault, 'itest');
    s.put('itest', 'environment', 'e', 'tok', 'abc');
    await s.flush();
    expect(s.lastError, isNull);
    final again = await VaultSecretStore.load(vault, 'itest');
    expect(again.values('itest', 'environment', 'e'), {'tok': 'abc'});
    again.remove('itest', 'environment', 'e', 'tok');
    await again.flush();
  });

  // The CLI reads these entries with the `security` tool (--vault), so the
  // service and account names must match what the app writes. Only the
  // attributes are looked up: reading the value (-w) makes macOS ask the user
  // to allow access, which would hang a CI run.
  testWidgets('macOS entries have the names the CLI looks up', (_) async {
    final vault = PlatformSecretVault();
    await vault.write('verbnest.cli-compat', 'cli-value');
    try {
      final r = await Process.run('security', [
        'find-generic-password',
        '-s',
        'flutter_secure_storage_service',
        '-a',
        'verbnest.cli-compat',
      ]);
      expect(r.exitCode, 0, reason: '${r.stderr}');
    } finally {
      await vault.delete('verbnest.cli-compat');
    }
  }, skip: !Platform.isMacOS);
}
