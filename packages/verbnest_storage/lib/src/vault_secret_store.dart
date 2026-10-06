import 'dart:convert';

import 'secret_store.dart';

/// Minimal async key/value interface over an OS secret store (Keychain,
/// Keystore, libsecret, Credential Manager). The app supplies the adapter.
abstract interface class SecretVault {
  Future<String?> read(String key);
  Future<void> write(String key, String value);
  Future<void> delete(String key);
}

/// [SecretStore] over a [SecretVault].
///
/// Reads are served from memory because variable resolution is synchronous.
/// Changes write through to the vault; the whole workspace is one JSON blob
/// so an update is a single vault write. A failed write is kept in
/// [lastError] and the value stays in memory for this session.
class VaultSecretStore implements SecretStore {
  VaultSecretStore._(this._vault, this.workspaceId, this._cache);

  final SecretVault _vault;
  final String workspaceId;
  final Map<String, String> _cache;
  Object? lastError;
  Future<void> _pending = Future.value();

  static String vaultKey(String workspaceId) => 'verbnest.secrets.$workspaceId';

  /// The key used before the rename from PostIt.
  static String legacyVaultKey(String workspaceId) =>
      'postit.secrets.$workspaceId';

  static String _k(String kind, String id, String key) =>
      jsonEncode([kind, id, key]);

  static Future<VaultSecretStore> load(
    SecretVault vault,
    String workspaceId,
  ) async {
    var raw = await vault.read(vaultKey(workspaceId));
    final fromLegacy = raw == null || raw.isEmpty;
    if (fromLegacy) raw = await vault.read(legacyVaultKey(workspaceId));
    final cache = <String, String>{};
    if (raw != null && raw.isNotEmpty) {
      final decoded = jsonDecode(raw);
      if (decoded is Map) {
        decoded.forEach((k, v) => cache['$k'] = '$v');
      }
    }
    final store = VaultSecretStore._(vault, workspaceId, cache);
    if (fromLegacy && cache.isNotEmpty) {
      // Move the entry to the new key; drop the old one only once the write
      // went through.
      store._persist();
      await store.flush();
      if (store.lastError == null) {
        try {
          await vault.delete(legacyVaultKey(workspaceId));
        } catch (_) {
          // The old entry is harmless; the new key wins from now on.
        }
      }
    }
    return store;
  }

  /// Completes when every queued write has finished.
  Future<void> flush() => _pending;

  void _persist() {
    final blob = jsonEncode(_cache);
    _pending = _pending.then((_) async {
      try {
        if (_cache.isEmpty) {
          await _vault.delete(vaultKey(workspaceId));
        } else {
          await _vault.write(vaultKey(workspaceId), blob);
        }
        lastError = null;
      } catch (e) {
        lastError = e;
      }
    });
  }

  @override
  Map<String, String> values(String ws, String kind, String id) {
    _check(ws);
    final out = <String, String>{};
    _cache.forEach((k, v) {
      final parts = jsonDecode(k) as List;
      if (parts[0] == kind && parts[1] == id) out['${parts[2]}'] = v;
    });
    return out;
  }

  @override
  void put(String ws, String kind, String id, String key, String value) {
    _check(ws);
    _cache[_k(kind, id, key)] = value;
    _persist();
  }

  @override
  void remove(String ws, String kind, String id, String key) {
    _check(ws);
    if (_cache.remove(_k(kind, id, key)) != null) _persist();
  }

  void _check(String ws) {
    if (ws != workspaceId) {
      throw ArgumentError('Store is bound to workspace $workspaceId, got $ws');
    }
  }
}

/// Probes [vault] with a throwaway entry. Returns false when the platform
/// store is unavailable (e.g. Linux without a keyring service).
Future<bool> vaultWorks(SecretVault vault) async {
  const key = 'verbnest.probe';
  try {
    await vault.write(key, 'ok');
    final ok = await vault.read(key) == 'ok';
    await vault.delete(key);
    return ok;
  } catch (_) {
    return false;
  }
}

/// Copies secrets from [from] into [to] for the given owners. Existing values
/// in [to] win. With [removeSource] the copies are also deleted from [from];
/// pass false first, confirm [to] persisted, then call [removeSecrets].
void migrateSecrets(
  SecretStore from,
  SecretStore to,
  String workspaceId,
  Iterable<(String kind, String id)> owners, {
  bool removeSource = true,
}) {
  for (final (kind, id) in owners) {
    final old = from.values(workspaceId, kind, id);
    if (old.isEmpty) continue;
    final have = to.values(workspaceId, kind, id);
    old.forEach((key, value) {
      if (!have.containsKey(key)) to.put(workspaceId, kind, id, key, value);
      if (removeSource) from.remove(workspaceId, kind, id, key);
    });
  }
}

/// Deletes every secret of the given owners from [store].
void removeSecrets(
  SecretStore store,
  String workspaceId,
  Iterable<(String kind, String id)> owners,
) {
  for (final (kind, id) in owners) {
    for (final key in store.values(workspaceId, kind, id).keys) {
      store.remove(workspaceId, kind, id, key);
    }
  }
}
