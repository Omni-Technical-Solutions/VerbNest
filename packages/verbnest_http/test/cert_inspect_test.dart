import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:test/test.dart';
import 'package:verbnest_http/verbnest_http.dart';

/// Certificates and keys made with `openssl` in a temporary folder, so no
/// private key is kept in the repository. The tests skip where it is missing.
class _Files {
  _Files(this.dir);

  final Directory dir;

  Uint8List read(String name) => File('${dir.path}/$name').readAsBytesSync();
  String path(String name) => '${dir.path}/$name';
}

Future<ProcessResult?> _openssl(List<String> args) async {
  try {
    return await Process.run('openssl', args);
  } on ProcessException {
    return null;
  }
}

Future<_Files?> _make() async {
  final dir = await Directory.systemTemp.createTemp('verbnest-cert');
  final f = _Files(dir);
  Future<bool> run(List<String> args) async =>
      (await _openssl(args))?.exitCode == 0;
  final ok =
      await run([
        'req', '-x509', '-newkey', 'rsa:2048', '-nodes', //
        '-keyout', f.path('rsa.key'), '-out', f.path('rsa.crt'),
        '-days', '30', '-subj', '/CN=client1/O=Example',
        '-addext', 'subjectAltName=DNS:a.test,IP:127.0.0.1,email:me@a.test',
      ]) &&
      await run([
        'req',
        '-x509',
        '-newkey',
        'ec',
        '-pkeyopt',
        'ec_paramgen_curve:P-256', //
        '-nodes', '-keyout', f.path('ec.key'), '-out', f.path('ec.crt'),
        '-days', '30', '-subj', '/CN=ec1',
      ]) &&
      await run([
        'req', '-x509', '-newkey', 'rsa:2048', '-nodes', //
        '-keyout', f.path('other.key'), '-out', f.path('other.crt'),
        '-days', '30', '-subj', '/CN=other',
      ]) &&
      await run([
        'pkcs8', '-topk8', '-in', f.path('rsa.key'), //
        '-out', f.path('rsa.enc.key'), '-passout', 'pass:secret',
      ]) &&
      await run([
        'pkcs12', '-export', '-in', f.path('rsa.crt'), //
        '-inkey', f.path('rsa.key'), '-out', f.path('modern.p12'),
        '-passout', 'pass:hunter2',
      ]);
  if (!ok) {
    await dir.delete(recursive: true);
    return null;
  }
  // An old-style bundle (3DES); not every OpenSSL still offers the options.
  await run([
    'pkcs12', '-export', '-in', f.path('rsa.crt'), '-inkey', f.path('rsa.key'),
    '-out', f.path('old.p12'), '-passout', 'pass:hunter2', //
    '-certpbe', 'PBE-SHA1-3DES', '-keypbe', 'PBE-SHA1-3DES', '-macalg', 'sha1',
  ]);
  // What `openssl pkcs12 -nodes` writes: `Bag Attributes` and `subject=` text
  // in front of every block, certificate and key in one file.
  await run([
    'pkcs12', '-in', f.path('modern.p12'), '-nodes', //
    '-passin', 'pass:hunter2', '-out', f.path('headed.pem'),
  ]);
  // Two certificates in one PEM, like a chain.
  File(f.path('chain.pem'))
      .writeAsBytesSync([...f.read('rsa.crt'), ...f.read('other.crt')]);
  return f;
}

void main() {
  _Files? files;
  setUpAll(() async => files = await _make());
  tearDownAll(() async {
    final f = files;
    if (f != null) await f.dir.delete(recursive: true);
  });

  _Files need() {
    final f = files;
    if (f == null) markTestSkipped('openssl not found');
    return f!;
  }

  group('reading a certificate', () {
    test('an RSA certificate says what it contains', () {
      final f = need();
      final info = parseCertificate(f.read('rsa.crt'));
      expect(info.subject, 'CN=client1, O=Example');
      expect(info.issuer, info.subject);
      expect(info.selfSigned, isTrue);
      expect(info.keyAlgorithm, 'RSA 2048');
      expect(
        info.names,
        containsAll(['DNS:a.test', 'IP:127.0.0.1', 'email:me@a.test']),
      );
      final now = DateTime.now().toUtc();
      expect(info.isNotYetValid(now), isFalse);
      expect(info.daysLeft(now), inInclusiveRange(28, 30));
      expect(info.serialHex, isNotEmpty);
    });

    test('the fingerprints equal the ones openssl prints', () async {
      final f = need();
      final info = parseCertificate(f.read('rsa.crt'));
      final r = await _openssl([
        'x509',
        '-in',
        f.path('rsa.crt'),
        '-noout',
        '-fingerprint',
        '-sha256', //
      ]);
      expect(r!.stdout.toString().trim().split('=').last, info.sha256);
      // The public key as DER, without a shell (there is none on Windows).
      final pubPem = await _openssl([
        'x509', '-in', f.path('rsa.crt'), '-pubkey', '-noout', //
      ]);
      File(f.path('pub.pem')).writeAsStringSync(pubPem!.stdout.toString());
      final der = await Process.run('openssl', [
        'pkey', '-pubin', '-in', f.path('pub.pem'), '-outform', 'der', //
      ], stdoutEncoding: null);
      expect(
        info.spkiSha256,
        sha256
            .convert(der.stdout as List<int>)
            .bytes
            .map((b) => b.toRadixString(16).padLeft(2, '0').toUpperCase())
            .join(':'),
      );
    });

    test('an elliptic-curve certificate', () {
      final f = need();
      expect(parseCertificate(f.read('ec.crt')).keyAlgorithm, 'EC P-256');
    });

    test('DER and PEM give the same answer', () async {
      final f = need();
      final r = await Process.run('openssl', [
        'x509', '-in', f.path('rsa.crt'), '-outform', 'der', //
      ], stdoutEncoding: null);
      final der = Uint8List.fromList(r.stdout as List<int>);
      final a = parseCertificate(der);
      final b = parseCertificate(f.read('rsa.crt'));
      expect(a.sha256, b.sha256);
      expect(a.subject, b.subject);
      expect(a.notAfter, b.notAfter);
    });

    test('a chain gives every certificate; a key alone gives an error', () {
      final f = need();
      final chain = parseCertificates(f.read('chain.pem'));
      expect(chain.map((c) => c.subject), [
        'CN=client1, O=Example',
        'CN=other',
      ]);
      expect(
        () => parseCertificate(f.read('rsa.key')),
        throwsA(isA<CertFormatException>()),
      );
    });

    test('anything else is a CertFormatException and nothing more', () {
      final r = Random(20261123);
      final f = files;
      final seeds = [
        if (f != null) f.read('rsa.crt'),
        if (f != null) f.read('ec.crt'),
        Uint8List.fromList(List.generate(200, (i) => i)),
      ];
      final rounds =
          int.tryParse(Platform.environment['FUZZ_ROUNDS'] ?? '') ?? 2000;
      for (var i = 0; i < rounds; i++) {
        final seed = seeds[r.nextInt(seeds.length)];
        final bytes = Uint8List.fromList([
          for (final b in seed.take(
            r.nextBool() ? seed.length : r.nextInt(seed.length + 1),
          ))
            r.nextInt(25) == 0 ? r.nextInt(256) : b,
        ]);
        try {
          parseCertificates(bytes);
        } on CertFormatException {
          // Refused, and said so.
        } on Object catch (e, st) {
          fail('${e.runtimeType} for ${bytes.take(60).toList()}:\n$e\n$st');
        }
      }
    });
  });

  group('checking a client certificate', () {
    CertCheck check(
      String cert, {
      String? key,
      String pass = '',
      DateTime? now,
      int soonDays = 7,
    }) {
      final f = need();
      return checkClientCertificate(
        certificate: f.read(cert),
        privateKey: key == null ? null : f.read(key),
        passphrase: pass,
        now: now,
        soonDays: soonDays,
      );
    }

    test('a certificate with its key loads, with details', () {
      final c = check('rsa.crt', key: 'rsa.key');
      expect(c.ok, isTrue);
      expect(c.info!.subject, contains('client1'));
      expect(c.warnings, [CertWarning.selfSigned]);
    });

    test('a key of another certificate is a mismatch', () {
      final c = check('rsa.crt', key: 'other.key');
      expect(c.problem, CertProblem.keyMismatch);
      expect(c.message, contains('does not match'));
    });

    test('a PEM certificate without a key asks for one', () {
      expect(check('rsa.crt').problem, CertProblem.keyMissing);
    });

    test('an encrypted key: right, wrong and missing passphrase', () {
      expect(check('rsa.crt', key: 'rsa.enc.key', pass: 'secret').ok, isTrue);
      final wrong = check('rsa.crt', key: 'rsa.enc.key', pass: 'nope');
      expect(wrong.problem, CertProblem.wrongPassphrase);
      expect(wrong.message, contains('wrong'));
      final none = check('rsa.crt', key: 'rsa.enc.key');
      expect(none.problem, CertProblem.wrongPassphrase);
      expect(none.message, contains('passphrase'));
    });

    test('a PKCS#12 bundle: right, wrong and missing passphrase', () {
      final ok = check('modern.p12', pass: 'hunter2');
      expect(ok.ok, isTrue);
      expect(ok.info, isNull);
      expect(
        check('modern.p12', pass: 'x').problem,
        CertProblem.wrongPassphrase,
      );
      expect(check('modern.p12').message, contains('needs a passphrase'));
    });

    test('an old 3DES bundle loads when openssl can make one', () {
      final f = need();
      if (!File(f.path('old.p12')).existsSync()) {
        return markTestSkipped('this openssl cannot write 3DES bundles');
      }
      expect(check('old.p12', pass: 'hunter2').ok, isTrue);
    });

    test('files that are not certificates', () {
      expect(
        checkClientCertificate(certificate: Uint8List.fromList([1, 2, 3]))
            .problem,
        CertProblem.notACertificate,
      );
      expect(
        checkClientCertificate(certificate: Uint8List(0)).problem,
        CertProblem.notACertificate,
      );
      // A private key chosen where the certificate belongs.
      expect(check('rsa.key').problem, CertProblem.notACertificate);
    });

    test('expiry is a warning, not an error', () {
      final f = need();
      final info = parseCertificate(f.read('rsa.crt'));
      CertCheck at(DateTime when) =>
          check('rsa.crt', key: 'rsa.key', now: when);
      final soon = at(info.notAfter.subtract(const Duration(days: 5)));
      expect(soon.ok, isTrue);
      expect(soon.warnings, contains(CertWarning.expiresSoon));
      final late = at(info.notAfter.add(const Duration(days: 1)));
      expect(late.ok, isTrue);
      expect(late.warnings, contains(CertWarning.expired));
      final early = at(info.notBefore.subtract(const Duration(days: 1)));
      expect(early.ok, isTrue);
      expect(early.warnings, contains(CertWarning.notYetValid));
      final fine = at(info.notBefore.add(const Duration(days: 1)));
      expect(fine.warnings, isNot(contains(CertWarning.expiresSoon)));
    });

    test('no message carries the key or the passphrase', () {
      final f = need();
      final keyText = base64Encode(f.read('rsa.key'));
      for (final c in [
        check('rsa.crt', key: 'other.key'),
        check('rsa.crt', key: 'rsa.enc.key', pass: 'secret-xyz-123'),
        check('modern.p12', pass: 'secret-xyz-123'),
      ]) {
        final text = '${c.message} ${c.problem}';
        expect(text, isNot(contains('secret-xyz-123')));
        expect(text, isNot(contains(keyText.substring(0, 40))));
      }
    });
  });

  group('text before the first PEM block', () {
    Uint8List headed(Uint8List pem, int headerBytes) {
      final text = StringBuffer('Bag Attributes\n');
      while (text.length < headerBytes) {
        text.write('subject=/CN=client1/O=Example Organisation\n');
      }
      return Uint8List.fromList([...utf8.encode(text.toString()), ...pem]);
    }

    test('looksLikePem sees a block after any amount of text', () {
      final f = need();
      final crt = f.read('rsa.crt');
      expect(looksLikePem(crt), isTrue);
      for (final n in [94, 300, 5000]) {
        expect(looksLikePem(headed(crt, n)), isTrue, reason: '$n bytes');
      }
      expect(
        looksLikePem(
          Uint8List.fromList(crt.map((b) => b == 13 ? 10 : b).toList()),
        ),
        isTrue,
      );
      expect(looksLikePem(f.read('modern.p12')), isFalse);
      expect(looksLikePem(Uint8List(0)), isFalse);
      expect(
        looksLikePem(Uint8List.fromList(utf8.encode('plain text'))),
        isFalse,
      );
    });

    test('hasPrivateKeyBlock finds a key, encrypted or not, anywhere', () {
      final f = need();
      expect(hasPrivateKeyBlock(f.read('rsa.crt')), isFalse);
      expect(hasPrivateKeyBlock(f.read('rsa.key')), isTrue);
      expect(hasPrivateKeyBlock(f.read('rsa.enc.key')), isTrue);
      expect(hasPrivateKeyBlock(f.read('headed.pem')), isTrue);
    });

    test('a headed certificate asks for its key, and loads with it', () {
      final f = need();
      for (final n in [94, 300]) {
        final crt = headed(f.read('rsa.crt'), n);
        final alone = checkClientCertificate(certificate: crt);
        expect(alone.problem, CertProblem.keyMissing, reason: '$n bytes');
        final withKey = checkClientCertificate(
          certificate: crt,
          privateKey: headed(f.read('rsa.key'), n),
        );
        expect(withKey.ok, isTrue, reason: '$n bytes: ${withKey.message}');
        expect(withKey.info!.subject, contains('client1'));
      }
    });

    test('a combined file from openssl pkcs12 -nodes loads on its own', () {
      final f = need();
      final both = f.read('headed.pem');
      expect(String.fromCharCodes(both.take(20)), contains('Bag Attributes'));
      final c = checkClientCertificate(certificate: both, privateKey: both);
      expect(c.ok, isTrue, reason: c.message);
    });
  });

  test('fingerprintOf is SHA-256 in hex with colons', () {
    expect(
      fingerprintOf(utf8.encode('abc')),
      sha256
          .convert(utf8.encode('abc'))
          .bytes
          .map((b) => b.toRadixString(16).padLeft(2, '0').toUpperCase())
          .join(':'),
    );
  });
}
