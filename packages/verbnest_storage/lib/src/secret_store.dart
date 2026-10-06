import 'local_store.dart';

/// Where secret variable values live. They are never written to the
/// workspace file (ADR-007, constitution II).
///
/// The interface is synchronous because variable resolution is. A platform
/// keychain adapter (Keychain, Keystore, libsecret, Credential Manager) must
/// load its values before use and write through.
abstract interface class SecretStore {
  Map<String, String> values(
    String workspaceId,
    String ownerKind,
    String ownerId,
  );

  void put(
    String workspaceId,
    String ownerKind,
    String ownerId,
    String key,
    String value,
  );

  void remove(String workspaceId, String ownerKind, String ownerId, String key);
}

/// Interim store backed by the device-local database. It is not encrypted;
/// use it only until a keychain adapter is available.
class LocalDbSecretStore implements SecretStore {
  LocalDbSecretStore(this._local);

  final LocalStore _local;

  @override
  Map<String, String> values(String ws, String kind, String id) =>
      _local.currentValues(ws, kind, id);

  @override
  void put(String ws, String kind, String id, String key, String value) =>
      _local.setCurrentValue(ws, kind, id, key, value);

  @override
  void remove(String ws, String kind, String id, String key) =>
      _local.clearCurrentValue(ws, kind, id, key);
}
