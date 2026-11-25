import 'dart:convert';
import 'dart:typed_data';

import 'package:test/test.dart';
import 'package:test_server/test_server.dart';
import 'package:verbnest_http/verbnest_http.dart';

Uint8List _der(List<int> pem) {
  final body = latin1
      .decode(pem)
      .split('\n')
      .where((l) => l.isNotEmpty && !l.startsWith('-----'))
      .join();
  return base64Decode(body);
}

void main() {
  late bool available;
  late Uint8List cert;
  late Uint8List key;

  setUpAll(() async {
    available = await TestServer.tlsAvailable;
    if (!available) return;
    final (c, k) = await TestServer.selfSignedCertificate();
    cert = Uint8List.fromList(c);
    key = Uint8List.fromList(k);
  });

  test('a valid CA file is accepted and described', () {
    if (!available) return markTestSkipped('openssl not found');
    final r = checkCaCertificates(
      cert,
      now: parseCertificate(cert).notBefore.add(const Duration(hours: 1)),
    );
    expect(r.ok, isTrue, reason: r.message);
    expect(r.certs.single.subject, contains('localhost'));
  });

  test('a bundle lists every certificate', () {
    if (!available) return markTestSkipped('openssl not found');
    final both = Uint8List.fromList([...cert, ...cert]);
    expect(checkCaCertificates(both).certs, hasLength(2));
  });

  test('a DER certificate is accepted and stored as PEM', () {
    if (!available) return markTestSkipped('openssl not found');
    final r = checkCaCertificates(_der(cert));
    expect(r.ok, isTrue, reason: r.message);
    expect(latin1.decode(r.pem!), startsWith('-----BEGIN CERTIFICATE-----'));
    // The PEM is the same certificate and loads as a trusted root.
    expect(parseCertificate(r.pem!).sha256, parseCertificate(cert).sha256);
  });

  test('a private key, garbage, an empty file and a cut PEM are refused', () {
    if (!available) return markTestSkipped('openssl not found');
    expect(checkCaCertificates(key).message, contains('no CERTIFICATE block'));
    expect(checkCaCertificates(Uint8List.fromList([1, 2, 3])).ok, isFalse);
    expect(checkCaCertificates(Uint8List(0)).ok, isFalse);
    final cut = cert.sublist(0, cert.length ~/ 2);
    expect(checkCaCertificates(Uint8List.fromList(cut)).ok, isFalse);
  });

  test('an expired or not yet valid CA is refused, one ending soon warns', () {
    if (!available) return markTestSkipped('openssl not found');
    final info = parseCertificate(cert);
    final late = checkCaCertificates(
      cert,
      now: info.notAfter.add(const Duration(days: 1)),
    );
    expect(late.ok, isFalse);
    expect(late.message, contains('expired on'));
    final early = checkCaCertificates(
      cert,
      now: info.notBefore.subtract(const Duration(days: 1)),
    );
    expect(early.message, contains('not valid until'));
    final soon = checkCaCertificates(
      cert,
      now: info.notAfter.subtract(const Duration(days: 5)),
    );
    expect(soon.ok, isTrue);
    expect(soon.warnings, [CertWarning.expiresSoon]);
  });
}
