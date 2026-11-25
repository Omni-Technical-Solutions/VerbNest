import 'cert_inspect.dart';
import 'errors.dart';
import 'tls_config.dart';

/// A server key (and certificate) that a host is expected to present
/// (FR-HTTP-013d). The key's SHA-256 is what is compared: a certificate that
/// is renewed with the same key still matches.
class PinEntry {
  const PinEntry({
    required this.host,
    this.port = 443,
    required this.spki,
    this.leaf,
    this.subject = '',
    this.issuer = '',
    this.notAfter,
    this.firstSeen,
    this.enabled = true,
    this.manual = false,
  });

  final String host;
  final int port;

  /// SHA-256 of the public key, upper-case hex with colons.
  final String spki;

  /// SHA-256 of the certificate last seen with that key, or null.
  final String? leaf;
  final String subject;
  final String issuer;
  final DateTime? notAfter;
  final DateTime? firstSeen;

  /// Off: kept in the list, never checked.
  final bool enabled;

  /// Set by the person (the app's pin list, `--pin`) and not recorded by the
  /// engine on first use.
  final bool manual;

  /// Whether [info]'s key (or, for a pin given as a certificate hash, the
  /// certificate itself) is the pinned one.
  bool matches(CertInfo info) =>
      normalizeFingerprint(spki) == info.spkiSha256 ||
      // A pin the person gave as a certificate hash (`--pin host=hash`) is
      // compared with the certificate too; a recorded one is a key only.
      (manual && leaf != null && normalizeFingerprint(leaf!) == info.sha256);

  /// `host:port`, how the list and the messages name it.
  String get label => port == 443 ? host : '$host:$port';

  PinEntry copyWith({
    String? spki,
    String? leaf,
    String? subject,
    String? issuer,
    DateTime? notAfter,
    bool? enabled,
    bool? manual,
  }) => PinEntry(
    host: host,
    port: port,
    spki: spki ?? this.spki,
    leaf: leaf ?? this.leaf,
    subject: subject ?? this.subject,
    issuer: issuer ?? this.issuer,
    notAfter: notAfter ?? this.notAfter,
    firstSeen: firstSeen,
    enabled: enabled ?? this.enabled,
    manual: manual ?? this.manual,
  );

  /// The pin a first connection leaves behind.
  factory PinEntry.firstUse(
    String host,
    int port,
    CertInfo info,
    DateTime now,
  ) => PinEntry(
    host: host.toLowerCase(),
    port: port,
    spki: info.spkiSha256,
    leaf: info.sha256,
    subject: info.subject,
    issuer: info.issuer,
    notAfter: info.notAfter,
    firstSeen: now,
  );

  Map<String, Object?> toJson() => {
    'host': host,
    if (port != 443) 'port': port,
    'spki': spki,
    if (leaf != null) 'leaf': leaf,
    if (subject.isNotEmpty) 'subject': subject,
    if (issuer.isNotEmpty) 'issuer': issuer,
    if (notAfter != null) 'notAfter': notAfter!.toUtc().toIso8601String(),
    if (firstSeen != null) 'firstSeen': firstSeen!.toUtc().toIso8601String(),
    if (!enabled) 'enabled': false,
    if (manual) 'manual': true,
  };

  static PinEntry fromJson(Map<dynamic, dynamic> j) => PinEntry(
    host: (j['host'] as String).toLowerCase(),
    port: j['port'] as int? ?? 443,
    spki: j['spki'] as String,
    leaf: j['leaf'] as String?,
    subject: j['subject'] as String? ?? '',
    issuer: j['issuer'] as String? ?? '',
    notAfter: j['notAfter'] == null
        ? null
        : DateTime.parse(j['notAfter'] as String),
    firstSeen: j['firstSeen'] == null
        ? null
        : DateTime.parse(j['firstSeen'] as String),
    enabled: j['enabled'] as bool? ?? true,
    manual: j['manual'] as bool? ?? false,
  );
}

/// A SHA-256 written any common way (`ab:cd`, `ABCD`, `abcd`) as the form
/// [CertInfo] uses: upper-case hex pairs with colons. Anything that is not 32
/// bytes of hex is returned in upper case unchanged.
String normalizeFingerprint(String text) {
  final hex = text.replaceAll(RegExp(r'[\s:]'), '').toUpperCase();
  if (!RegExp(r'^[0-9A-F]{64}$').hasMatch(hex)) return text.toUpperCase();
  return [for (var i = 0; i < 64; i += 2) hex.substring(i, i + 2)].join(':');
}

/// The pins in force for a run or a session. The engine records the first
/// key a host presents here; [onChanged] lets the app save them.
class PinBook {
  PinBook([Iterable<PinEntry> entries = const [], this.onChanged])
    : _entries = [...entries];

  final List<PinEntry> _entries;

  /// Called with the whole list after every change.
  void Function(List<PinEntry> entries)? onChanged;

  /// Accept a changed key for a recorded (not manual) pin and update it, as
  /// `--trust-changed` does.
  bool trustChanges = false;

  /// Called when a pinned host presented another key and the connection is
  /// about to be refused.
  void Function(PinEntry pin, CertInfo actual)? onMismatch;

  List<PinEntry> get entries => List.unmodifiable(_entries);

  PinEntry? lookup(String host, int port) {
    final h = host.toLowerCase();
    for (final e in _entries) {
      if (e.host == h && e.port == port) return e;
    }
    return null;
  }

  /// Adds [entry], or replaces the one for the same host and port.
  void put(PinEntry entry) {
    final i = _entries.indexWhere(
      (e) => e.host == entry.host && e.port == entry.port,
    );
    if (i < 0) {
      _entries.add(entry);
    } else {
      _entries[i] = entry;
    }
    onChanged?.call(entries);
  }

  void remove(String host, int port) {
    final h = host.toLowerCase();
    _entries.removeWhere((e) => e.host == h && e.port == port);
    onChanged?.call(entries);
  }
}

/// How a connection's server key compared with the pins.
enum PinStatus {
  /// Pinning does not apply to this host.
  notApplicable,

  /// It applies, but the pin is switched off.
  disabled,

  /// It applies, but the certificate was not verified (verification is off or
  /// the certificate is untrusted), so nothing is recorded or compared.
  unverified,

  /// First connection: the key was recorded.
  recorded,

  /// The key is the pinned one.
  matches,

  /// The key is not the pinned one.
  mismatch,
}

class PinCheck {
  const PinCheck(this.status, [this.entry]);

  final PinStatus status;

  /// The pin that applied (before any update).
  final PinEntry? entry;
}

/// The server key changed: the connection is closed before anything is sent.
class PinMismatchError extends TlsError {
  PinMismatchError(this.pin, this.actual)
    : super(
        'The certificate of ${pin.label} changed. Pinned key '
        '${pin.spki} (${pin.subject.isEmpty ? 'certificate not recorded' : pin.subject}'
        '${pin.notAfter == null ? '' : ', expires ${_day(pin.notAfter!)}'}), '
        'now ${actual.spkiSha256} (${actual.subject}, expires ${_day(actual.notAfter)}). '
        'Trust the new key only if the change is expected.',
      );

  final PinEntry pin;
  final CertInfo actual;

  static String _day(DateTime d) =>
      d.toUtc().toIso8601String().substring(0, 10);
}

/// Whether a pin is in play for [host]:[port]: an entry for it exists, or
/// pinning by default is on and the host has a client certificate.
bool pinApplies(TlsConfig? tls, String host, int port) {
  final book = tls?.pins;
  if (tls == null || book == null) return false;
  return book.lookup(host, port) != null ||
      (tls.pinByDefault && tls.clientCertificateFor(host, port: port) != null);
}

/// Compares the server's [leaf] certificate with the pins in [tls] for
/// [host]:[port], recording the key on first use. Pinning applies to a host
/// that has a pin, and (unless switched off) to every host a client
/// certificate entry applies to. Nothing is recorded or compared when
/// [verified] is false, or when [record] is false only the comparison is
/// made.
PinCheck checkPin(
  TlsConfig? tls,
  String host,
  int port,
  CertInfo leaf, {
  required bool verified,
  bool record = true,
  DateTime? now,
}) {
  final book = tls?.pins;
  if (tls == null || book == null) {
    return const PinCheck(PinStatus.notApplicable);
  }
  final entry = book.lookup(host, port);
  if (!pinApplies(tls, host, port)) {
    return const PinCheck(PinStatus.notApplicable);
  }
  if (entry != null && !entry.enabled) {
    return PinCheck(PinStatus.disabled, entry);
  }
  if (!verified) return PinCheck(PinStatus.unverified, entry);
  if (entry == null) {
    if (record) {
      book.put(PinEntry.firstUse(host, port, leaf, now ?? DateTime.now()));
    }
    return const PinCheck(PinStatus.recorded);
  }
  if (!entry.matches(leaf)) {
    if (book.trustChanges && !entry.manual) {
      if (record) {
        book.put(
          entry.copyWith(
            spki: leaf.spkiSha256,
            leaf: leaf.sha256,
            subject: leaf.subject,
            issuer: leaf.issuer,
            notAfter: leaf.notAfter,
          ),
        );
      }
      return PinCheck(PinStatus.recorded, entry);
    }
    book.onMismatch?.call(entry, leaf);
    return PinCheck(PinStatus.mismatch, entry);
  }
  // Same key: keep the certificate details current after a renewal.
  if (record && !entry.manual && entry.leaf != leaf.sha256) {
    book.put(
      entry.copyWith(
        leaf: leaf.sha256,
        subject: leaf.subject,
        issuer: leaf.issuer,
        notAfter: leaf.notAfter,
      ),
    );
  }
  return PinCheck(PinStatus.matches, entry);
}
