import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:postit_storage/postit_storage.dart';

/// [SecretVault] over the platform secret store via `flutter_secure_storage`.
class PlatformSecretVault implements SecretVault {
  PlatformSecretVault([FlutterSecureStorage? storage])
    : _s =
          storage ??
          // The data-protection keychain needs the keychain-access-groups
          // entitlement and a provisioning profile, which ad-hoc signed
          // macOS builds do not have. The legacy keychain works without.
          const FlutterSecureStorage(
            mOptions: MacOsOptions(usesDataProtectionKeychain: false),
          );

  final FlutterSecureStorage _s;

  @override
  Future<String?> read(String key) => _s.read(key: key);

  @override
  Future<void> write(String key, String value) =>
      _s.write(key: key, value: value);

  @override
  Future<void> delete(String key) => _s.delete(key: key);
}
