import 'package:verbnest_storage/verbnest_storage.dart';
import 'package:test/test.dart';

class _MemVault implements SecretVault {
  final data = <String, String>{};
  bool fail = false;
  @override
  Future<String?> read(String key) async {
    if (fail) throw StateError('no keyring');
    return data[key];
  }

  @override
  Future<void> write(String key, String value) async {
    if (fail) throw StateError('no keyring');
    data[key] = value;
  }

  @override
  Future<void> delete(String key) async {
    if (fail) throw StateError('no keyring');
    data.remove(key);
  }
}

void main() {
  test('values round trip through the vault and reload', () async {
    final vault = _MemVault();
    final s = await VaultSecretStore.load(vault, 'w1');
    s.put('w1', 'environment', 'e1', 'token', 'abc');
    s.put('w1', 'environment', 'e2', 'token', 'zzz');
    expect(s.values('w1', 'environment', 'e1'), {'token': 'abc'});
    await s.flush();
    expect(vault.data.keys, ['verbnest.secrets.w1']);

    final again = await VaultSecretStore.load(vault, 'w1');
    expect(again.values('w1', 'environment', 'e2'), {'token': 'zzz'});
    again.remove('w1', 'environment', 'e1', 'token');
    again.remove('w1', 'environment', 'e2', 'token');
    await again.flush();
    expect(vault.data, isEmpty);
  });

  test('keys with odd characters do not collide', () async {
    final s = await VaultSecretStore.load(_MemVault(), 'w');
    s.put('w', 'a', 'b.c', 'd', '1');
    s.put('w', 'a.b', 'c', 'd', '2');
    expect(s.values('w', 'a', 'b.c'), {'d': '1'});
    expect(s.values('w', 'a.b', 'c'), {'d': '2'});
  });

  test(
    'a failing vault keeps values in memory and records the error',
    () async {
      final vault = _MemVault();
      final s = await VaultSecretStore.load(vault, 'w');
      vault.fail = true;
      s.put('w', 'k', 'i', 'x', 'v');
      await s.flush();
      expect(s.lastError, isNotNull);
      expect(s.values('w', 'k', 'i'), {'x': 'v'});
    },
  );

  test('wrong workspace is rejected', () async {
    final s = await VaultSecretStore.load(_MemVault(), 'w');
    expect(() => s.values('other', 'k', 'i'), throwsArgumentError);
  });

  test('vaultWorks probes and cleans up', () async {
    final v = _MemVault();
    expect(await vaultWorks(v), isTrue);
    expect(v.data, isEmpty);
    v.fail = true;
    expect(await vaultWorks(v), isFalse);
  });

  test(
    'migrateSecrets moves values and keeps existing target values',
    () async {
      final local = LocalStore.memory();
      final from = LocalDbSecretStore(local);
      from.put('w', 'environment', 'e', 'a', '1');
      from.put('w', 'environment', 'e', 'b', '2');
      final to = await VaultSecretStore.load(_MemVault(), 'w');
      to.put('w', 'environment', 'e', 'b', 'new');
      migrateSecrets(from, to, 'w', [('environment', 'e')]);
      expect(to.values('w', 'environment', 'e'), {'a': '1', 'b': 'new'});
      expect(from.values('w', 'environment', 'e'), isEmpty);
    },
  );

  test('removeSource false keeps the source until removeSecrets', () async {
    final local = LocalStore.memory();
    final from = LocalDbSecretStore(local);
    from.put('w', 'environment', 'e', 'a', '1');
    final to = await VaultSecretStore.load(_MemVault(), 'w');
    migrateSecrets(from, to, 'w', [('environment', 'e')], removeSource: false);
    expect(from.values('w', 'environment', 'e'), {'a': '1'});
    removeSecrets(from, 'w', [('environment', 'e')]);
    expect(from.values('w', 'environment', 'e'), isEmpty);
  });

  test('secrets saved under the pre-rename key move to the new key', () async {
    final v = _MemVault();
    v.data[VaultSecretStore.legacyVaultKey('w')] =
        '{"[\\"environment\\",\\"e\\",\\"k\\"]":"s3"}';
    final store = await VaultSecretStore.load(v, 'w');
    expect(store.values('w', 'environment', 'e'), {'k': 's3'});
    expect(v.data.containsKey(VaultSecretStore.legacyVaultKey('w')), isFalse);
    expect(v.data.containsKey(VaultSecretStore.vaultKey('w')), isTrue);
    final again = await VaultSecretStore.load(v, 'w');
    expect(again.values('w', 'environment', 'e'), {'k': 's3'});
  });
}
