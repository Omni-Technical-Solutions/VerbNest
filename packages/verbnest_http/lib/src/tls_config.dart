import 'dart:io';
import 'dart:typed_data';

import 'pin.dart';

/// A client certificate offered to hosts that match [hostPattern]
/// (FR-HTTP-013, FR-HTTP-013b). Either PEM ([certificate] plus [privateKey])
/// or a PKCS#12 bundle in [certificate] with no [privateKey].
///
/// Patterns: `api.example.com`, `*.example.com`, `*`, with an optional port
/// (`api.example.com:8443`) and an optional `https://` in front. When several
/// entries match, the most specific one is used (see [TlsConfig.selectFor]).
class ClientCertificate {
  const ClientCertificate({
    required this.hostPattern,
    required this.certificate,
    this.privateKey,
    this.passphrase = '',
    this.enabled = true,
    this.label = '',
  }) : isNone = false;

  /// An entry that says "send no client certificate" to the hosts it matches,
  /// beating any broader entry (for example a `*` entry).
  ClientCertificate.none(
    this.hostPattern, {
    this.enabled = true,
    this.label = '',
  }) : certificate = Uint8List(0),
       privateKey = null,
       passphrase = '',
       isNone = true;

  final String hostPattern;
  final Uint8List certificate;
  final Uint8List? privateKey;
  final String passphrase;

  /// A switched-off entry is kept but never matches.
  final bool enabled;

  /// What the person calls it (the file name by default); shown in the TLS
  /// panel as the entry that was used.
  final String label;

  /// True for a [ClientCertificate.none] entry.
  final bool isNone;

  bool get isPkcs12 => privateKey == null && !isNone;

  /// How specifically this entry names [host] on [port]; negative when it does
  /// not match. Exact host beats `*.suffix` (longer suffix first) beats `*`,
  /// and a pattern with a port beats the same pattern without.
  int specificity(String host, {int? port}) {
    final p = _Pattern.parse(hostPattern);
    final h = host.toLowerCase();
    if (p.port != null && p.port != port) return -1;
    final bonus = p.port != null ? 1000 : 0;
    if (p.host == '*') return bonus + 1;
    if (p.host.startsWith('*.')) {
      final suffix = p.host.substring(1);
      return h.endsWith(suffix) && h.length > suffix.length
          ? bonus + 100 + suffix.length
          : -1;
    }
    return h == p.host ? bonus + 500 : -1;
  }

  bool matches(String host, {int? port}) => specificity(host, port: port) >= 0;
}

class _Pattern {
  const _Pattern(this.host, this.port);

  final String host;
  final int? port;

  static _Pattern parse(String raw) {
    var t = raw.trim().toLowerCase();
    final scheme = t.indexOf('://');
    if (scheme >= 0) t = t.substring(scheme + 3);
    final slash = t.indexOf('/');
    if (slash >= 0) t = t.substring(0, slash);
    int? port;
    final colon = t.lastIndexOf(':');
    // A bracketed IPv6 literal keeps its colons; only a trailing :digits is a port.
    if (colon > 0 && !t.endsWith(']')) {
      final n = int.tryParse(t.substring(colon + 1));
      if (n != null) {
        port = n;
        t = t.substring(0, colon);
      }
    }
    return _Pattern(t.isEmpty ? '*' : t, port);
  }
}

/// The oldest TLS version a connection may use.
enum TlsVersion { v12, v13 }

/// TLS material beyond the system trust store: extra CA certificates and
/// per-host client certificates.
class TlsConfig {
  const TlsConfig({
    this.caCertificates = const [],
    this.clientCertificates = const [],
    this.pins,
    this.pinByDefault = true,
    this.minimumVersion,
  });

  /// PEM or DER bytes, added to the trusted roots.
  final List<Uint8List> caCertificates;
  final List<ClientCertificate> clientCertificates;

  /// Pinned server keys, and where the first key a host presents is recorded
  /// (FR-HTTP-013d). Null means no pinning.
  final PinBook? pins;

  /// Whether a host that has a client certificate entry is pinned on first
  /// use even without a pin of its own.
  final bool pinByDefault;

  /// The oldest TLS version to accept: [TlsVersion.v12] (the default of the
  /// platform library) or [TlsVersion.v13].
  final TlsVersion? minimumVersion;

  bool get isEmpty =>
      caCertificates.isEmpty &&
      clientCertificates.isEmpty &&
      pins == null &&
      minimumVersion == null;

  /// The entry that applies to [host] on [port]: the most specific enabled
  /// match, the first one added when two are equally specific. A
  /// [ClientCertificate.none] entry is returned like any other, so the caller
  /// can tell "none on purpose" from "nothing matched" (null).
  ClientCertificate? selectFor(String host, {int? port}) {
    ClientCertificate? best;
    var bestScore = -1;
    for (final c in clientCertificates) {
      if (!c.enabled) continue;
      final score = c.specificity(host, port: port);
      if (score > bestScore) {
        best = c;
        bestScore = score;
      }
    }
    return best;
  }

  /// The certificate that will be presented to [host] on [port], or null.
  ClientCertificate? clientCertificateFor(String host, {int? port}) {
    final c = selectFor(host, port: port);
    return c == null || c.isNone ? null : c;
  }

  /// A context for a connection to [host]. Throws [TlsException] when a
  /// certificate or key cannot be read, e.g. a wrong passphrase.
  SecurityContext contextFor(String host, {int? port}) {
    final context = SecurityContext(withTrustedRoots: true);
    if (minimumVersion == TlsVersion.v13) {
      context.minimumTlsProtocolVersion = TlsProtocolVersion.tls1_3;
    }
    for (final ca in caCertificates) {
      context.setTrustedCertificatesBytes(ca);
    }
    final match = clientCertificateFor(host, port: port);
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
    this.clientCertificateLabel,
    this.fingerprint,
    this.spkiFingerprint,
    this.names = const [],
    this.pin = PinStatus.notApplicable,
  });

  final String subject;
  final String issuer;
  final DateTime validFrom;
  final DateTime validTo;

  /// ALPN protocol, e.g. `http/1.1`.
  final String? protocol;
  final bool clientCertificateSent;

  /// The name of the client-certificate entry that was configured for this
  /// host, when one was.
  final String? clientCertificateLabel;

  /// SHA-256 of the server's certificate, upper-case hex with colons.
  final String? fingerprint;

  /// SHA-256 of its public key; unchanged when the certificate is renewed
  /// with the same key (the value to pin).
  final String? spkiFingerprint;

  /// The names the certificate covers (`DNS:api.example.com`, `IP:...`).
  final List<String> names;

  /// How the server key compared with the pins (FR-HTTP-013d).
  final PinStatus pin;
}
