import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:verbnest_http/verbnest_http.dart';

/// The channel the native keystore code listens on (macOS, iOS, Android,
/// Linux, Windows; FR-HTTP-013f). Methods: `supported`, `identities`,
/// `import`, `open`, `close`.
const keystoreChannelName = 'com.omni.verbnest/keystore';

/// [KeystoreRelay] over a platform channel. The native side holds the keys and
/// does the TLS; this only passes names and bytes.
class PlatformKeystoreRelay implements KeystoreRelay {
  PlatformKeystoreRelay({MethodChannel? channel})
    : _channel = channel ?? const MethodChannel(keystoreChannelName);

  final MethodChannel _channel;
  bool? _supported;

  @override
  bool get isSupported => _supported ?? false;

  /// Asks the platform whether it has a keystore bridge; call once at start.
  Future<bool> probe() => _probing ??= _probe();

  Future<bool>? _probing;

  Future<bool> _probe() async {
    try {
      _supported = await _channel.invokeMethod<bool>('supported') ?? false;
    } on Object {
      // No plugin on this platform, or no Flutter binding yet (plain unit
      // tests): there is no keystore.
      _supported = false;
    }
    return _supported!;
  }

  @override
  Future<List<KeystoreIdentity>> identities() async {
    try {
      final list =
          await _channel.invokeListMethod<Map<dynamic, dynamic>>(
            'identities',
          ) ??
          const [];
      return [for (final m in list) KeystoreIdentity.fromJson(m)];
    } on PlatformException catch (e) {
      throw KeystoreError(e.message ?? 'The keystore could not be read.');
    } on MissingPluginException {
      throw const KeystoreError('This build has no keystore bridge.');
    }
  }

  /// Imports a PKCS#12 file into the system keystore (the key is kept by the
  /// system, not by VerbNest) and returns the identity.
  Future<KeystoreIdentity> import(
    Uint8List bytes,
    String passphrase,
    String label,
  ) async {
    try {
      final m = await _channel.invokeMapMethod<dynamic, dynamic>('import', {
        'bytes': bytes,
        'passphrase': passphrase,
        'label': label,
      });
      return KeystoreIdentity.fromJson(m!);
    } on PlatformException catch (e) {
      throw KeystoreError(e.message ?? 'The file could not be imported.');
    }
  }

  /// Android: shows the system's certificate chooser (credentials installed
  /// in Settings) and returns the one picked.
  Future<KeystoreIdentity> choose() async {
    try {
      final m = await _channel.invokeMapMethod<dynamic, dynamic>('choose');
      return KeystoreIdentity.fromJson(m!);
    } on PlatformException catch (e) {
      throw KeystoreError(e.message ?? 'No certificate was chosen.');
    }
  }

  /// Removes an identity from the system keystore (the certificate and key).
  Future<void> remove(String identityId) async {
    try {
      await _channel.invokeMethod<void>('remove', {'identity': identityId});
    } on PlatformException catch (e) {
      throw KeystoreError(e.message ?? 'The identity could not be removed.');
    }
  }

  @override
  Future<RelaySession> open(RelayRequest r) async {
    try {
      final m = await _channel.invokeMapMethod<dynamic, dynamic>('open', {
        'host': r.host,
        'port': r.port,
        'identity': r.identityId,
        'cas': r.caCertificates,
        'minVersion': switch (r.minimumVersion) {
          TlsVersion.v13 => '1.3',
          TlsVersion.v12 => '1.2',
          null => null,
        },
        'verify': r.verify,
        'protocols': r.protocols,
      });
      return _ChannelSession(_channel, m!);
    } on PlatformException catch (e) {
      throw KeystoreError(e.message ?? 'The keystore connection failed.');
    }
  }
}

class _ChannelSession implements RelaySession {
  _ChannelSession(this._channel, Map<dynamic, dynamic> m)
    : _id = m['session'] as String,
      port = m['port'] as int,
      serverCertificate = m['certificate'] as Uint8List?,
      protocol = m['protocol'] as String?,
      handshakeTime = Duration(
        milliseconds: (m['handshakeMs'] as num?)?.round() ?? 0,
      );

  final MethodChannel _channel;
  final String _id;
  var _closed = false;

  @override
  final int port;
  @override
  final Uint8List? serverCertificate;
  @override
  final String? protocol;
  @override
  final Duration handshakeTime;

  @override
  Future<void> close() async {
    if (_closed) return;
    _closed = true;
    try {
      await _channel.invokeMethod<void>('close', {'session': _id});
    } on Object {
      // Already gone.
    }
  }
}

/// The relay the app uses; tests override it. It is created at start and
/// asked once whether the platform has a bridge.
final keystoreRelayProvider = Provider<KeystoreRelay>((ref) {
  final r = PlatformKeystoreRelay();
  if (!kIsWeb) unawaited(r.probe());
  return r;
});

/// Whether the platform has a keystore bridge (known after the first probe).
final keystoreSupportedProvider = FutureProvider<bool>((ref) async {
  final r = ref.watch(keystoreRelayProvider);
  return r is PlatformKeystoreRelay ? r.probe() : r.isSupported;
});
