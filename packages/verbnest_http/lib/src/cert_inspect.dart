import 'dart:convert';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';

/// What a certificate says about itself (FR-HTTP-013a). Read from the DER
/// bytes without any TLS library, so it works for a file that has not been
/// loaded into a connection yet and for the certificate a server presented.
class CertInfo {
  const CertInfo({
    required this.subject,
    required this.issuer,
    required this.serialHex,
    required this.notBefore,
    required this.notAfter,
    required this.names,
    required this.keyAlgorithm,
    required this.sha256,
    required this.spkiSha256,
    required this.selfSigned,
  });

  /// Distinguished names as `CN=client1, O=Example`.
  final String subject;
  final String issuer;
  final String serialHex;
  final DateTime notBefore;
  final DateTime notAfter;

  /// Subject alternative names: `DNS:a.test`, `IP:10.0.0.1`, `email:x@y`,
  /// `URI:https://x`.
  final List<String> names;

  /// `RSA 2048`, `EC P-256`, `Ed25519`, or the algorithm's OID.
  final String keyAlgorithm;

  /// SHA-256 of the whole certificate as upper-case hex with colons, the form
  /// browsers and `openssl x509 -fingerprint -sha256` show.
  final String sha256;

  /// SHA-256 of the public key (SubjectPublicKeyInfo). It does not change
  /// when a certificate is renewed with the same key, which makes it the
  /// right value to pin (plan phase D).
  final String spkiSha256;
  final bool selfSigned;

  /// Whole days from [now] to the end of validity; negative once expired.
  int daysLeft(DateTime now) => notAfter.difference(now).inDays;

  /// Whether the certificate names [host]: a DNS or IP subject alternative
  /// name (`*.example.com` covers one label), or, when there are none, the
  /// common name.
  bool coversHost(String host) {
    final h = host.toLowerCase().replaceAll(RegExp(r'^\[|\]$'), '');
    final sans = names
        .where((n) => n.startsWith('DNS:') || n.startsWith('IP:'))
        .map((n) => n.substring(n.indexOf(':') + 1).toLowerCase())
        .toList();
    final candidates = sans.isNotEmpty
        ? sans
        : [
            for (final part in subject.split(', '))
              if (part.startsWith('CN=')) part.substring(3).toLowerCase(),
          ];
    for (final c in candidates) {
      if (c == h) return true;
      if (c.startsWith('*.')) {
        final rest = c.substring(1);
        if (h.endsWith(rest) &&
            !h.substring(0, h.length - rest.length).contains('.') &&
            h.length > rest.length) {
          return true;
        }
      }
    }
    return false;
  }

  bool isExpired(DateTime now) => now.isAfter(notAfter);
  bool isNotYetValid(DateTime now) => now.isBefore(notBefore);
}

/// A file or byte string that is not a readable certificate.
class CertFormatException implements Exception {
  const CertFormatException(this.message);

  final String message;

  @override
  String toString() => message;
}

/// Every certificate in [bytes]: the `CERTIFICATE` blocks of a PEM file (a
/// chain has several; other blocks such as private keys are skipped), or one
/// DER certificate. Throws [CertFormatException] when there is none or one is
/// malformed. Never throws anything else, whatever the input.
List<CertInfo> parseCertificates(Uint8List bytes) {
  try {
    final text = latin1.decode(bytes, allowInvalid: true);
    if (text.contains('-----BEGIN')) {
      final blocks = _pemBlocks(text, 'CERTIFICATE');
      if (blocks.isEmpty) {
        throw const CertFormatException(
          'The file has no CERTIFICATE block (a private key alone is not a '
          'certificate)',
        );
      }
      return [for (final der in blocks) _parseCertificate(der)];
    }
    return [_parseCertificate(bytes)];
  } on CertFormatException {
    rethrow;
  } on Object {
    throw const CertFormatException('The data is not a valid certificate');
  }
}

/// The first certificate in [bytes] (the leaf of a chain).
CertInfo parseCertificate(Uint8List bytes) => parseCertificates(bytes).first;

/// SHA-256 of [der] as upper-case hex with colons.
String fingerprintOf(List<int> der) => _hex(sha256.convert(der).bytes, ':');

List<Uint8List> _pemBlocks(String text, String label) {
  final re = RegExp('-----BEGIN $label-----([\\s\\S]*?)-----END $label-----');
  return [
    for (final m in re.allMatches(text))
      base64Decode(m.group(1)!.replaceAll(RegExp(r'\s+'), '')),
  ];
}

String _hex(List<int> bytes, String sep) => bytes
    .map((b) => b.toRadixString(16).padLeft(2, '0').toUpperCase())
    .join(sep);

// ---- DER reader ---------------------------------------------------------

/// One tag-length-value element.
class _Tlv {
  _Tlv(this.tag, this.start, this.valueStart, this.end);

  final int tag;
  final int start;
  final int valueStart;
  final int end;
}

class _Der {
  _Der(this.bytes);

  final Uint8List bytes;

  /// The element at [offset]; the length must fit inside [limit].
  _Tlv read(int offset, int limit) {
    if (offset + 2 > limit) throw const CertFormatException('Truncated data');
    final tag = bytes[offset];
    var p = offset + 1;
    var len = bytes[p++];
    if (len & 0x80 != 0) {
      final n = len & 0x7f;
      if (n == 0 || n > 4 || p + n > limit) {
        throw const CertFormatException('Bad length');
      }
      len = 0;
      for (var i = 0; i < n; i++) {
        len = (len << 8) | bytes[p++];
      }
    }
    if (len < 0 || p + len > limit) {
      throw const CertFormatException('Length past the end');
    }
    return _Tlv(tag, offset, p, p + len);
  }

  /// The children of a constructed element.
  List<_Tlv> children(_Tlv parent) {
    final out = <_Tlv>[];
    var p = parent.valueStart;
    while (p < parent.end) {
      final t = read(p, parent.end);
      out.add(t);
      p = t.end;
    }
    return out;
  }

  Uint8List value(_Tlv t) => Uint8List.sublistView(bytes, t.valueStart, t.end);
  Uint8List whole(_Tlv t) => Uint8List.sublistView(bytes, t.start, t.end);
}

const _sequence = 0x30;
const _set = 0x31;
const _oid = 0x06;
const _integer = 0x02;
const _bitString = 0x03;
const _utcTime = 0x17;
const _generalizedTime = 0x18;

CertInfo _parseCertificate(Uint8List der) {
  final d = _Der(der);
  final cert = d.read(0, der.length);
  if (cert.tag != _sequence) {
    throw const CertFormatException('The data is not a certificate');
  }
  final top = d.children(cert);
  if (top.isEmpty || top.first.tag != _sequence) {
    throw const CertFormatException('The data is not a certificate');
  }
  final tbs = d.children(top.first);
  var i = 0;
  if (tbs.isNotEmpty && tbs[0].tag == 0xa0) i++; // [0] version
  if (tbs.length < i + 6) {
    throw const CertFormatException('The certificate is incomplete');
  }
  final serial = tbs[i];
  final issuer = tbs[i + 2];
  final validity = tbs[i + 3];
  final subject = tbs[i + 4];
  final spki = tbs[i + 5];
  if (serial.tag != _integer ||
      issuer.tag != _sequence ||
      validity.tag != _sequence ||
      subject.tag != _sequence ||
      spki.tag != _sequence) {
    throw const CertFormatException('The certificate is malformed');
  }
  final times = d.children(validity);
  if (times.length != 2) {
    throw const CertFormatException('The validity period is malformed');
  }

  final names = <String>[];
  for (final t in tbs.skip(i + 6)) {
    if (t.tag == 0xa3) {
      for (final ext in d.children(d.children(t).first)) {
        final parts = d.children(ext);
        if (parts.isNotEmpty && _oidString(d, parts.first) == '2.5.29.17') {
          // The value is an OCTET STRING holding the GeneralNames.
          final octets = parts.last;
          final inner = d.read(octets.valueStart, octets.end);
          names.addAll(_generalNames(d, inner));
        }
      }
    }
  }

  final issuerDer = d.whole(issuer);
  final subjectDer = d.whole(subject);
  return CertInfo(
    subject: _name(d, subject),
    issuer: _name(d, issuer),
    serialHex: _hex(d.value(serial), ''),
    notBefore: _time(d, times[0]),
    notAfter: _time(d, times[1]),
    names: names,
    keyAlgorithm: _keyAlgorithm(d, spki),
    sha256: fingerprintOf(der),
    spkiSha256: fingerprintOf(d.whole(spki)),
    selfSigned: _same(issuerDer, subjectDer),
  );
}

bool _same(Uint8List a, Uint8List b) {
  if (a.length != b.length) return false;
  for (var i = 0; i < a.length; i++) {
    if (a[i] != b[i]) return false;
  }
  return true;
}

String _oidString(_Der d, _Tlv t) {
  if (t.tag != _oid) return '';
  final v = d.value(t);
  if (v.isEmpty) return '';
  final parts = <int>[v[0] ~/ 40, v[0] % 40];
  var n = 0;
  for (var k = 1; k < v.length; k++) {
    n = (n << 7) | (v[k] & 0x7f);
    if (v[k] & 0x80 == 0) {
      parts.add(n);
      n = 0;
    }
  }
  return parts.join('.');
}

const _attributeNames = {
  '2.5.4.3': 'CN',
  '2.5.4.5': 'serialNumber',
  '2.5.4.6': 'C',
  '2.5.4.7': 'L',
  '2.5.4.8': 'ST',
  '2.5.4.10': 'O',
  '2.5.4.11': 'OU',
  '1.2.840.113549.1.9.1': 'emailAddress',
  '0.9.2342.19200300.100.1.25': 'DC',
};

String _name(_Der d, _Tlv name) {
  final parts = <String>[];
  for (final rdn in d.children(name)) {
    if (rdn.tag != _set) continue;
    for (final atv in d.children(rdn)) {
      final kv = d.children(atv);
      if (kv.length != 2) continue;
      final key = _oidString(d, kv[0]);
      parts.add('${_attributeNames[key] ?? key}=${_string(d, kv[1])}');
    }
  }
  return parts.join(', ');
}

String _string(_Der d, _Tlv t) {
  final v = d.value(t);
  // BMPString (0x1e) is UTF-16BE; the others are single-byte or UTF-8.
  if (t.tag == 0x1e) {
    final units = <int>[
      for (var k = 0; k + 1 < v.length; k += 2) (v[k] << 8) | v[k + 1],
    ];
    return String.fromCharCodes(units);
  }
  return utf8.decode(v, allowMalformed: true);
}

DateTime _time(_Der d, _Tlv t) {
  if (t.tag != _utcTime && t.tag != _generalizedTime) {
    throw const CertFormatException('A date is malformed');
  }
  final s = latin1.decode(d.value(t));
  final m = t.tag == _utcTime
      ? RegExp(r'^(\d{2})(\d{2})(\d{2})(\d{2})(\d{2})(\d{2})?Z$').firstMatch(s)
      : RegExp(r'^(\d{4})(\d{2})(\d{2})(\d{2})(\d{2})(\d{2})?Z$').firstMatch(s);
  if (m == null) throw const CertFormatException('A date is malformed');
  var year = int.parse(m.group(1)!);
  if (t.tag == _utcTime) year += year >= 50 ? 1900 : 2000;
  return DateTime.utc(
    year,
    int.parse(m.group(2)!),
    int.parse(m.group(3)!),
    int.parse(m.group(4)!),
    int.parse(m.group(5)!),
    int.parse(m.group(6) ?? '0'),
  );
}

List<String> _generalNames(_Der d, _Tlv seq) {
  final out = <String>[];
  for (final g in d.children(seq)) {
    final v = d.value(g);
    switch (g.tag) {
      case 0x82:
        out.add('DNS:${latin1.decode(v)}');
      case 0x81:
        out.add('email:${latin1.decode(v)}');
      case 0x86:
        out.add('URI:${latin1.decode(v)}');
      case 0x87:
        out.add('IP:${_ip(v)}');
    }
  }
  return out;
}

String _ip(Uint8List v) {
  if (v.length == 4) return v.join('.');
  if (v.length == 16) {
    return [
      for (var k = 0; k < 16; k += 2)
        ((v[k] << 8) | v[k + 1]).toRadixString(16),
    ].join(':');
  }
  return _hex(v, '');
}

const _ecCurves = {
  '1.2.840.10045.3.1.7': 'P-256',
  '1.3.132.0.34': 'P-384',
  '1.3.132.0.35': 'P-521',
};

String _keyAlgorithm(_Der d, _Tlv spki) {
  final parts = d.children(spki);
  if (parts.length != 2) return 'unknown';
  final alg = d.children(parts[0]);
  if (alg.isEmpty) return 'unknown';
  final oid = _oidString(d, alg[0]);
  switch (oid) {
    case '1.2.840.113549.1.1.1':
      return 'RSA ${_rsaBits(d, parts[1])}';
    case '1.2.840.10045.2.1':
      final curve = alg.length > 1 ? _oidString(d, alg[1]) : '';
      return 'EC ${_ecCurves[curve] ?? curve}';
    case '1.3.101.112':
      return 'Ed25519';
    case '1.3.101.113':
      return 'Ed448';
    default:
      return oid.isEmpty ? 'unknown' : oid;
  }
}

int _rsaBits(_Der d, _Tlv bits) {
  if (bits.tag != _bitString) return 0;
  final v = d.value(bits);
  if (v.length < 2) return 0;
  // Skip the unused-bits byte; the rest is SEQUENCE { INTEGER n, INTEGER e }.
  final inner = _Der(Uint8List.sublistView(v, 1));
  final seq = inner.read(0, inner.bytes.length);
  final kids = inner.children(seq);
  if (kids.isEmpty || kids.first.tag != _integer) return 0;
  final n = inner.value(kids.first);
  var k = 0;
  while (k < n.length && n[k] == 0) {
    k++;
  }
  if (k == n.length) return 0;
  return (n.length - k) * 8 - (7 - _highBit(n[k]));
}

/// Index (0 to 7) of the highest set bit.
int _highBit(int b) {
  var i = 7;
  while (i > 0 && (b >> i) & 1 == 0) {
    i--;
  }
  return i;
}
