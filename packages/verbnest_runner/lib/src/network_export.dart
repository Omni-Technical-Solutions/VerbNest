import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:cryptography/cryptography.dart';

import 'network_settings.dart';

/// Why a network export could not be written or read.
class NetworkExportError implements Exception {
  const NetworkExportError(this.message);

  final String message;

  @override
  String toString() => message;
}

/// A file that carries the network settings, client certificates and private
/// keys from the app to the command line or to a CI job (FR-HTTP-013c).
///
/// The file is JSON with a header and an encrypted body: the key is derived
/// from a passphrase the person types with PBKDF2-HMAC-SHA256 and a random
/// salt, and the body is sealed with AES-256-GCM. A wrong passphrase and a
/// changed file are both refused; nothing in the file is readable without it.
class NetworkExport {
  static const format = 'verbnest-network';
  static const version = 1;

  /// PBKDF2 rounds. OWASP's 2023 figure for HMAC-SHA256.
  static const defaultIterations = 600000;

  static Uint8List _random(int n) {
    final r = Random.secure();
    return Uint8List.fromList(List.generate(n, (_) => r.nextInt(256)));
  }

  static Future<SecretKey> _key(
    String passphrase,
    List<int> salt,
    int iterations,
  ) => Pbkdf2(
    macAlgorithm: Hmac.sha256(),
    iterations: iterations,
    bits: 256,
  ).deriveKeyFromPassword(password: passphrase, nonce: salt);

  static List<int> _aad(int iterations) =>
      utf8.encode('$format:$version:pbkdf2-sha256:$iterations:aes-256-gcm');

  /// The export file for [config], protected by [passphrase].
  static Future<Uint8List> encrypt(
    NetworkConfig config,
    String passphrase, {
    int iterations = defaultIterations,
  }) async {
    if (passphrase.isEmpty) {
      throw const NetworkExportError('Choose a passphrase for the export file');
    }
    final salt = _random(16);
    final nonce = _random(12);
    final plain = utf8.encode(
      jsonEncode({
        'config': NetworkConfigStore.toJson(config),
        'secrets': NetworkConfigStore.secretsOf(config),
      }),
    );
    final box = await AesGcm.with256bits().encrypt(
      plain,
      secretKey: await _key(passphrase, salt, iterations),
      nonce: nonce,
      aad: _aad(iterations),
    );
    return Uint8List.fromList(
      utf8.encode(
        const JsonEncoder.withIndent('  ').convert({
          'format': format,
          'version': version,
          'kdf': 'pbkdf2-hmac-sha256',
          'iterations': iterations,
          'cipher': 'aes-256-gcm',
          'salt': base64Encode(salt),
          'nonce': base64Encode(nonce),
          'data': base64Encode([...box.cipherText, ...box.mac.bytes]),
        }),
      ),
    );
  }

  /// The settings in [file], opened with [passphrase].
  static Future<NetworkConfig> decrypt(
    Uint8List file,
    String passphrase,
  ) async {
    final Map<String, Object?> head;
    final int iterations;
    final List<int> salt;
    final List<int> nonce;
    final List<int> data;
    try {
      head = jsonDecode(utf8.decode(file)) as Map<String, Object?>;
      iterations = head['iterations'] as int;
      salt = base64Decode(head['salt'] as String);
      nonce = base64Decode(head['nonce'] as String);
      data = base64Decode(head['data'] as String);
    } on Object {
      throw const NetworkExportError('This is not a VerbNest network export');
    }
    if (head['format'] != format) {
      throw const NetworkExportError('This is not a VerbNest network export');
    }
    if (head['version'] != version ||
        head['kdf'] != 'pbkdf2-hmac-sha256' ||
        head['cipher'] != 'aes-256-gcm') {
      throw NetworkExportError(
        'This export was made by a different version of VerbNest '
        '(format ${head['version']})',
      );
    }
    // A file cannot ask for an absurd amount of work, nor for none.
    if (iterations < 10000 || iterations > 5000000 || data.length < 16) {
      throw const NetworkExportError('This is not a VerbNest network export');
    }
    final List<int> plain;
    try {
      plain = await AesGcm.with256bits().decrypt(
        SecretBox(
          data.sublist(0, data.length - 16),
          nonce: nonce,
          mac: Mac(data.sublist(data.length - 16)),
        ),
        secretKey: await _key(passphrase, salt, iterations),
        aad: _aad(iterations),
      );
    } on SecretBoxAuthenticationError {
      throw const NetworkExportError(
        'The passphrase is wrong, or the file was changed',
      );
    }
    try {
      final j = jsonDecode(utf8.decode(plain)) as Map<String, Object?>;
      return NetworkConfigStore.readJson(
        (j['config']! as Map).cast<String, Object?>(),
        (j['secrets']! as Map).cast<String, String>(),
      );
    } on Object {
      throw const NetworkExportError('The export file is damaged');
    }
  }
}
