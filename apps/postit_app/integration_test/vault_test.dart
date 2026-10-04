import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:postit_app/src/state/secure_vault.dart';
import 'package:postit_storage/postit_storage.dart';

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
}
