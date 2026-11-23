import 'dart:convert';
import 'dart:typed_data';

import 'package:test/test.dart';
import 'package:verbnest_runner/verbnest_runner.dart';

NetworkConfig _config() => NetworkConfig(
  proxyHost: 'p.test',
  proxyEnabled: true,
  proxyPassword: 'pw-123-secret',
  clientCerts: [
    ClientCertEntry(
      id: 'a',
      pattern: 'api.test',
      name: 'API',
      certificate: Uint8List.fromList(utf8.encode('CERT')),
      privateKey: Uint8List.fromList(utf8.encode('PRIVATE-KEY-BYTES')),
      passphrase: 'hunter2-secret',
    ),
  ],
);

// Few rounds in tests; the default is the production figure.
const _rounds = 10000;

void main() {
  test('an export opens with the passphrase and restores everything', () async {
    final file = await NetworkExport.encrypt(
      _config(),
      'open sesame',
      iterations: _rounds,
    );
    final back = await NetworkExport.decrypt(file, 'open sesame');
    expect(back.proxyHost, 'p.test');
    expect(back.proxyPassword, 'pw-123-secret');
    final c = back.clientCerts.single;
    expect(utf8.decode(c.certificate), 'CERT');
    expect(utf8.decode(c.privateKey!), 'PRIVATE-KEY-BYTES');
    expect(c.passphrase, 'hunter2-secret');
  });

  test('nothing secret is readable in the file', () async {
    final file = await NetworkExport.encrypt(
      _config(),
      'open sesame',
      iterations: _rounds,
    );
    final text = utf8.decode(file);
    for (final secret in [
      'CERT',
      'PRIVATE-KEY',
      'hunter2',
      'pw-123',
      'open sesame',
    ]) {
      expect(text, isNot(contains(secret)));
    }
    expect(
      text,
      isNot(contains(base64Encode(utf8.encode('PRIVATE-KEY-BYTES')))),
    );
    final head = jsonDecode(text) as Map<String, Object?>;
    expect(head['format'], 'verbnest-network');
    expect(head['version'], 1);
    expect(head['iterations'], _rounds);
  });

  test('a wrong passphrase is refused', () async {
    final file = await NetworkExport.encrypt(
      _config(),
      'right',
      iterations: _rounds,
    );
    await expectLater(
      NetworkExport.decrypt(file, 'wrong'),
      throwsA(
        isA<NetworkExportError>().having(
          (e) => e.message,
          'm',
          contains('passphrase'),
        ),
      ),
    );
  });

  test('a changed file is refused', () async {
    final file = await NetworkExport.encrypt(
      _config(),
      'pass',
      iterations: _rounds,
    );
    final head = jsonDecode(utf8.decode(file)) as Map<String, Object?>;
    // Flip one bit in the body.
    final data = base64Decode(head['data']! as String);
    data[3] ^= 1;
    head['data'] = base64Encode(data);
    await expectLater(
      NetworkExport.decrypt(
        Uint8List.fromList(utf8.encode(jsonEncode(head))),
        'pass',
      ),
      throwsA(isA<NetworkExportError>()),
    );
    // The iteration count is part of what is authenticated.
    final head2 = jsonDecode(utf8.decode(file)) as Map<String, Object?>;
    head2['iterations'] = _rounds + 1;
    await expectLater(
      NetworkExport.decrypt(
        Uint8List.fromList(utf8.encode(jsonEncode(head2))),
        'pass',
      ),
      throwsA(isA<NetworkExportError>()),
    );
  });

  test('other files and absurd headers are refused quietly', () async {
    for (final junk in [
      Uint8List(0),
      Uint8List.fromList(utf8.encode('not json')),
      Uint8List.fromList(utf8.encode('{"format":"other"}')),
      Uint8List.fromList(
        utf8.encode(
          '{"format":"verbnest-network","version":2,"kdf":"x","cipher":"y","iterations":1,"salt":"AA==","nonce":"AA==","data":"AA=="}',
        ),
      ),
    ]) {
      await expectLater(
        NetworkExport.decrypt(junk, 'x'),
        throwsA(isA<NetworkExportError>()),
      );
    }
    final huge = {
      'format': 'verbnest-network', 'version': 1, 'kdf': 'pbkdf2-hmac-sha256',
      'cipher': 'aes-256-gcm', 'iterations': 900000000, //
      'salt': base64Encode(List.filled(16, 1)),
      'nonce': base64Encode(List.filled(12, 1)),
      'data': base64Encode(List.filled(40, 1)),
    };
    await expectLater(
      NetworkExport.decrypt(
        Uint8List.fromList(utf8.encode(jsonEncode(huge))),
        'x',
      ),
      throwsA(isA<NetworkExportError>()),
    );
  });

  test('an empty passphrase is refused when exporting', () async {
    await expectLater(
      NetworkExport.encrypt(_config(), ''),
      throwsA(isA<NetworkExportError>()),
    );
  });

  test('the default rounds finish in a reasonable time', () async {
    final sw = Stopwatch()..start();
    final file = await NetworkExport.encrypt(_config(), 'x');
    await NetworkExport.decrypt(file, 'x');
    // Two derivations at 600,000 rounds each, in pure Dart.
    expect(sw.elapsed, lessThan(const Duration(seconds: 30)));
    // ignore: avoid_print
    print('600k-round export + import: ${sw.elapsedMilliseconds} ms');
  });

  test(
    'a keystore identity is not exported: it exists only on this device',
    () async {
      final config = _config().copyWith(
        clientCerts: [
          ..._config().clientCerts,
          ClientCertEntry(
            id: 'k',
            pattern: 'corp.test',
            name: 'Work identity',
            certificate: Uint8List(0),
            keystoreId: 'AA:BB',
          ),
        ],
      );
      final file = await NetworkExport.encrypt(
        config,
        'pw',
        iterations: _rounds,
      );
      final back = await NetworkExport.decrypt(file, 'pw');
      expect(back.clientCerts.map((c) => c.id), ['a']);
    },
  );
}
