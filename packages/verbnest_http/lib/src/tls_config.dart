import 'dart:io';
import 'dart:typed_data';

/// A client certificate offered to hosts that match [hostPattern]
/// (FR-HTTP-013). Either PEM ([certificate] plus [privateKey]) or a
/// PKCS#12 bundle in [certificate] with no [privateKey].
class ClientCertificate {
  const ClientCertificate({
    required this.hostPattern,
    required this.certificate,
    this.privateKey,
    this.passphrase = '',
  });

  /// `api.example.com`, `*.example.com` or `*`.
  final String hostPattern;
  final Uint8List certificate;
  final Uint8List? privateKey;
  final String passphrase;

  bool get isPkcs12 => privateKey == null;

  bool matches(String host) {
    final p = hostPattern.trim().toLowerCase();
    final h = host.toLowerCase();
    if (p == '*') return true;
    if (p.startsWith('*.')) return h.endsWith(p.substring(1));
    return h == p;
  }
}

/// TLS material beyond the system trust store: extra CA certificates and
/// per-host client certificates.
class TlsConfig {
  const TlsConfig({
    this.caCertificates = const [],
    this.clientCertificates = const [],
  });

  /// PEM or DER bytes, added to the trusted roots.
  final List<Uint8List> caCertificates;
  final List<ClientCertificate> clientCertificates;

  bool get isEmpty => caCertificates.isEmpty && clientCertificates.isEmpty;

  /// A context for a connection to [host]. Throws [TlsException] when a
  /// certificate or key cannot be read, e.g. a wrong passphrase.
  SecurityContext contextFor(String host) {
    final context = SecurityContext(withTrustedRoots: true);
    for (final ca in caCertificates) {
      context.setTrustedCertificatesBytes(ca);
    }
    final match = clientCertificates.where((c) => c.matches(host)).firstOrNull;
    if (match != null) {
      final pass = match.passphrase.isEmpty ? null : match.passphrase;
      context.useCertificateChainBytes(match.certificate, password: pass);
      context.usePrivateKeyBytes(
        match.privateKey ?? match.certificate,
        password: pass,
      );
    }
    return context;
  }
}

/// What the server presented, for the response's TLS panel.
class TlsInfo {
  const TlsInfo({
    required this.subject,
    required this.issuer,
    required this.validFrom,
    required this.validTo,
    this.protocol,
    this.clientCertificateSent = false,
  });

  final String subject;
  final String issuer;
  final DateTime validFrom;
  final DateTime validTo;

  /// ALPN protocol, e.g. `http/1.1`.
  final String? protocol;
  final bool clientCertificateSent;
}
