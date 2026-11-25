import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'cert_inspect.dart';

/// Why a client certificate cannot be used.
enum CertProblem {
  /// The file is not a certificate or PKCS#12 bundle.
  notACertificate,

  /// A PEM certificate was given without its private key.
  keyMissing,

  /// The passphrase is wrong, or the key/bundle needs one.
  wrongPassphrase,

  /// The private key does not belong to the certificate.
  keyMismatch,

  /// The PKCS#12 bundle or key uses an encryption the TLS library cannot
  /// read; it can be re-exported with `openssl pkcs12 -export`.
  unsupported,

  /// Anything else the TLS library refused.
  unreadable,
}

/// Something worth telling the person that does not stop them saving.
enum CertWarning { expired, notYetValid, expiresSoon, selfSigned }

/// The outcome of [checkClientCertificate].
class CertCheck {
  const CertCheck({
    this.problem,
    this.message,
    this.info,
    this.warnings = const [],
  });

  /// Null when the certificate and key load together.
  final CertProblem? problem;

  /// A sentence for the person, set with [problem].
  final String? message;

  /// The leaf certificate's details; null for a PKCS#12 bundle (the TLS
  /// library does not expose what is inside) or when [problem] is set early.
  final CertInfo? info;
  final List<CertWarning> warnings;

  bool get ok => problem == null;
}

/// Loads [certificate] (with [privateKey], or as a PKCS#12 bundle when the key
/// is null) into a TLS context exactly the way the engine does, and reports
/// the first thing that is wrong, or what the certificate says about itself.
///
/// An expired or not yet valid certificate is a warning, not an error: an API
/// client is also used to test how a server answers one.
CertCheck checkClientCertificate({
  required Uint8List certificate,
  Uint8List? privateKey,
  String passphrase = '',
  DateTime? now,
  int soonDays = 30,
}) {
  final when = now ?? DateTime.now();
  final pass = passphrase.isEmpty ? null : passphrase;

  CertInfo? info;
  final pem = _isPem(certificate);
  if (pem) {
    try {
      info = parseCertificate(certificate);
    } on CertFormatException catch (e) {
      return CertCheck(
        problem: CertProblem.notACertificate,
        message: e.message,
      );
    }
    if (privateKey == null) {
      return const CertCheck(
        problem: CertProblem.keyMissing,
        message: 'This is a PEM certificate: choose its private key as well',
      );
    }
  }

  try {
    final context = SecurityContext(withTrustedRoots: false);
    // A PEM certificate is not encrypted; only the key (or a PKCS#12 bundle)
    // takes the passphrase, which keeps a wrong one reported as BAD_DECRYPT.
    context.useCertificateChainBytes(certificate, password: pem ? null : pass);
    context.usePrivateKeyBytes(privateKey ?? certificate, password: pass);
  } on Object catch (e) {
    return _classify(e, pem: pem, hasPassphrase: pass != null);
  }

  final warnings = <CertWarning>[];
  if (info != null) {
    if (info.isExpired(when)) {
      warnings.add(CertWarning.expired);
    } else if (info.isNotYetValid(when)) {
      warnings.add(CertWarning.notYetValid);
    } else if (info.daysLeft(when) < soonDays) {
      warnings.add(CertWarning.expiresSoon);
    }
    if (info.selfSigned) warnings.add(CertWarning.selfSigned);
  }
  return CertCheck(info: info, warnings: warnings);
}

/// Maps the TLS library's wording to a [CertProblem]. The strings are the
/// ones BoringSSL puts on its error queue (`KEY_VALUES_MISMATCH`,
/// `INCORRECT_PASSWORD`, `BAD_DECRYPT`, `BAD_PKCS12_DATA`) and the
/// `ArgumentError` `dart:io` raises for a key file it cannot use.
CertCheck _classify(
  Object e, {
  required bool pem,
  required bool hasPassphrase,
}) {
  final text =
      (e is TlsException ? '${e.message} ${e.osError?.message ?? ''}' : '$e')
          .toLowerCase();
  CertCheck problem(CertProblem p, String message) =>
      CertCheck(problem: p, message: message);

  if (text.contains('key_values_mismatch')) {
    return problem(
      CertProblem.keyMismatch,
      'The private key does not match the certificate',
    );
  }
  if (text.contains('incorrect_password') ||
      text.contains('bad_decrypt') ||
      text.contains('mac verify')) {
    return problem(
      CertProblem.wrongPassphrase,
      hasPassphrase
          ? 'The passphrase is wrong'
          : 'This file needs a passphrase',
    );
  }
  if (text.contains('expected private key')) {
    // dart:io says this for an encrypted key with the wrong or no passphrase,
    // and for a file that holds no private key at all.
    return problem(
      CertProblem.wrongPassphrase,
      hasPassphrase
          ? 'The passphrase is wrong, or the file is not a private key'
          : 'The key needs a passphrase, or the file is not a private key',
    );
  }
  if (text.contains('unsupported') ||
      text.contains('unknown_pbe') ||
      text.contains('unknown pbe') ||
      text.contains('unknown_algorithm')) {
    return problem(
      CertProblem.unsupported,
      'The encryption of this file is not supported. Re-export it with '
      '`openssl pkcs12 -export` (add `-legacy` if the file is old)',
    );
  }
  if (text.contains('bad_pkcs12_data') || text.contains('no start line')) {
    return problem(
      CertProblem.notACertificate,
      'This is not a certificate or a PKCS#12 bundle',
    );
  }
  return problem(
    CertProblem.unreadable,
    'The certificate could not be read: ${e is TlsException ? e.message : e}',
  );
}

bool _isPem(Uint8List bytes) {
  final head = String.fromCharCodes(bytes.take(200));
  return head.contains('-----BEGIN');
}

/// The outcome of [checkCaCertificates].
class CaCheck {
  const CaCheck({
    this.message,
    this.certs = const [],
    this.warnings = const [],
    this.pem,
  });

  /// The certificates as PEM, the form to store: `dart:io` loads trusted
  /// roots from PEM only, so a DER file is converted. Null when [message] is
  /// set.
  final Uint8List? pem;

  /// A sentence for the person when the file cannot be used as trusted CAs.
  final String? message;

  /// Every certificate in the file, in order.
  final List<CertInfo> certs;
  final List<CertWarning> warnings;

  bool get ok => message == null;
}

/// Checks a file of trusted CA certificates (PEM with one or more
/// certificates, or one DER certificate) the way the engine will use it: every
/// certificate is read, and the bytes are loaded into a TLS context as trusted
/// roots, so a file that parses but cannot be used is reported now.
///
/// An expired or not yet valid certificate is a [CaCheck.message] (it would
/// never validate a server); one that ends within [soonDays] is a warning.
CaCheck checkCaCertificates(
  Uint8List bytes, {
  DateTime? now,
  int soonDays = 30,
}) {
  final when = now ?? DateTime.now();
  final List<CertInfo> certs;
  try {
    certs = parseCertificates(bytes);
  } on CertFormatException catch (e) {
    return CaCheck(message: e.message);
  }
  for (final c in certs) {
    final date = c.notAfter.toIso8601String().substring(0, 10);
    if (c.isExpired(when)) {
      return CaCheck(
        certs: certs,
        message: '${c.subject} expired on $date, so it cannot be trusted',
      );
    }
    if (c.isNotYetValid(when)) {
      return CaCheck(
        certs: certs,
        message:
            '${c.subject} is not valid until '
            '${c.notBefore.toIso8601String().substring(0, 10)}',
      );
    }
  }
  final pem = _asPem(bytes);
  try {
    SecurityContext(withTrustedRoots: false).setTrustedCertificatesBytes(pem);
  } on Object catch (e) {
    return CaCheck(
      certs: certs,
      message:
          'The TLS library cannot load this file: '
          '${e.toString().split('\n').first}',
    );
  }
  final soon = certs.any((c) => c.daysLeft(when) < soonDays);
  return CaCheck(
    certs: certs,
    warnings: soon ? const [CertWarning.expiresSoon] : const [],
    pem: pem,
  );
}

/// [bytes] as PEM: a PEM file is returned as it is, one DER certificate is
/// wrapped in a `CERTIFICATE` block.
Uint8List _asPem(Uint8List bytes) {
  if (latin1.decode(bytes, allowInvalid: true).contains('-----BEGIN')) {
    return bytes;
  }
  final b64 = base64Encode(bytes);
  final lines = [
    for (var i = 0; i < b64.length; i += 64)
      b64.substring(i, i + 64 > b64.length ? b64.length : i + 64),
  ];
  return Uint8List.fromList(
    latin1.encode(
      '-----BEGIN CERTIFICATE-----\n${lines.join('\n')}\n'
      '-----END CERTIFICATE-----\n',
    ),
  );
}
