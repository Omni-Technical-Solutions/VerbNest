import 'dart:typed_data';

import 'tls_config.dart';

import 'errors.dart';

/// A certificate and private key held by the operating system (a Keychain
/// identity, an Android KeyStore entry, a smart card, a PKCS#11 token), chosen
/// by [id]. VerbNest never sees the key: signing happens in the platform's TLS
/// code (FR-HTTP-013f).
class KeystoreIdentity {
  const KeystoreIdentity({
    required this.id,
    required this.label,
    this.subject = '',
    this.issuer = '',
    this.notAfter,
    this.sha256 = '',
  });

  /// What a host entry stores: stable on this device (the certificate's
  /// SHA-256 on Apple platforms, the alias on Android).
  final String id;

  /// What the person sees in the list.
  final String label;
  final String subject;
  final String issuer;
  final DateTime? notAfter;

  /// SHA-256 of the certificate, upper-case hex with colons, when known.
  final String sha256;

  Map<String, Object?> toJson() => {
    'id': id,
    'label': label,
    'subject': subject,
    'issuer': issuer,
    if (notAfter != null) 'notAfter': notAfter!.toUtc().toIso8601String(),
    'sha256': sha256,
  };

  static KeystoreIdentity fromJson(Map<dynamic, dynamic> j) => KeystoreIdentity(
    id: j['id'] as String,
    label: j['label'] as String? ?? j['id'] as String,
    subject: j['subject'] as String? ?? '',
    issuer: j['issuer'] as String? ?? '',
    notAfter: j['notAfter'] == null
        ? null
        : DateTime.tryParse(j['notAfter'] as String),
    sha256: j['sha256'] as String? ?? '',
  );
}

/// What the relay is asked to connect to.
class RelayRequest {
  const RelayRequest({
    required this.host,
    required this.port,
    required this.identityId,
    this.caCertificates = const [],
    this.minimumVersion,
    this.verify = true,
    this.protocols = const ['http/1.1'],
  });

  final String host;
  final int port;
  final String identityId;

  /// Extra trusted CAs (PEM or DER), as in [TlsConfig.caCertificates].
  final List<Uint8List> caCertificates;
  final TlsVersion? minimumVersion;

  /// False when certificate checking is switched off for the request.
  final bool verify;

  /// ALPN protocols to offer.
  final List<String> protocols;
}

/// An open relay: plain TCP on `127.0.0.1:[port]` inside this process, which
/// the platform connects, with TLS and the identity, to the real server.
abstract interface class RelaySession {
  int get port;

  /// The server's certificate (DER), as the platform saw it.
  Uint8List? get serverCertificate;

  /// The ALPN protocol, when the platform says.
  String? get protocol;

  /// Time the handshake took.
  Duration get handshakeTime;

  Future<void> close();
}

/// The platform side of keystore identities. The app supplies one that talks
/// to native code; the engine uses it for host entries that name an identity.
abstract interface class KeystoreRelay {
  /// Whether this platform can do it at all.
  bool get isSupported;

  Future<List<KeystoreIdentity>> identities();

  /// Opens the relay for one connection. Throws [KeystoreError] when the
  /// identity is gone, locked or refused, or the handshake fails.
  Future<RelaySession> open(RelayRequest request);
}

/// A keystore identity could not be used.
class KeystoreError extends TlsError {
  const KeystoreError(super.message);
}
