import 'dart:async';
import 'dart:convert';
import 'dart:io' show Platform, gzip, zlib;
import 'dart:math';
import 'dart:typed_data';

import 'package:test/test.dart';
import 'package:verbnest_http/src/byte_reader.dart';
import 'package:verbnest_http/src/errors.dart';
import 'package:verbnest_http/src/response_reader.dart';

/// A server controls every byte of a response. The reader may reject what it
/// cannot parse, with a [ProtocolError] or another engine error, but never with
/// a range, state or type error (security review S10, plan phase F). Inputs come
/// from a fixed seed, so a failure repeats.
final _seeds = <List<int>>[
  latin1.encode(
    'HTTP/1.1 200 OK\r\nContent-Type: text/plain\r\nContent-Length: 5\r\n\r\nhello',
  ),
  latin1.encode(
    'HTTP/1.1 200 OK\r\nTransfer-Encoding: chunked\r\n\r\n'
    '5\r\nhello\r\n6;ext=1\r\n world\r\n0\r\nTrailer: x\r\n\r\n',
  ),
  latin1.encode(
    'HTTP/1.0 404 Not Found\r\nConnection: close\r\n\r\nbody until EOF',
  ),
  latin1.encode('HTTP/1.1 204 No Content\r\n\r\n'),
  latin1.encode(
    'HTTP/1.1 301 Moved\r\nLocation: /x\r\nContent-Length: 0\r\n\r\n',
  ),
];

List<int> _mutate(List<int> seed, Random r) {
  final out = <int>[];
  for (final b in seed) {
    switch (r.nextInt(30)) {
      case 0:
        break; // drop
      case 1:
        out
          ..add(r.nextInt(256))
          ..add(b);
      case 2:
        out.addAll(List.filled(1 + r.nextInt(20), b));
      case 3:
        return out; // truncate
      case 4:
        out.add(r.nextInt(256));
      default:
        out.add(b);
    }
  }
  return out;
}

/// The bytes split into random chunks, like a socket delivers them.
Stream<List<int>> _chunks(List<int> bytes, Random r) async* {
  var i = 0;
  while (i < bytes.length) {
    final n = 1 + r.nextInt(max(1, bytes.length));
    yield bytes.sublist(i, min(bytes.length, i + n));
    i += n;
  }
}

void main() {
  final count = int.tryParse(Platform.environment['FUZZ_ROUNDS'] ?? '') ?? 500;

  test('reading a response only fails with an engine error', () async {
    final r = Random(20261021);
    for (var i = 0; i < count; i++) {
      final input = i.isEven
          ? List<int>.generate(r.nextInt(150), (_) => r.nextInt(256))
          : _mutate(_seeds[r.nextInt(_seeds.length)], r);
      final reader = ByteReader(_chunks(input, r));
      final sw = Stopwatch()..start();
      try {
        final p = await readResponse(
          reader,
          sw,
          Duration.zero,
          method: r.nextInt(5) == 0 ? 'HEAD' : 'GET',
        ).timeout(const Duration(seconds: 5));
        decodeContentEncoding(p.headers, p.body);
      } on HttpEngineError {
        // Rejected, and said so.
      } on FormatException {
        // The engine turns this into a network error too.
      } on Object catch (e, st) {
        fail('${e.runtimeType} for ${input.take(200).toList()}:\n$e\n$st');
      }
    }
  });

  test('content decoding only fails with an engine error', () {
    final r = Random(20261021);
    final good = [
      gzip.encode(utf8.encode('hello world ' * 20)),
      zlib.encode(utf8.encode('hello world ' * 20)),
    ];
    for (var i = 0; i < count; i++) {
      final body = Uint8List.fromList(
        i.isEven
            ? List<int>.generate(r.nextInt(80), (_) => r.nextInt(256))
            : _mutate(good[r.nextInt(2)], r),
      );
      final encoding = ['gzip', 'x-gzip', 'deflate', 'br', ''][r.nextInt(5)];
      try {
        decodeContentEncoding([('Content-Encoding', encoding)], body);
      } on HttpEngineError {
        // Rejected, and said so.
      } on Object catch (e, st) {
        fail(
          '${e.runtimeType} for $encoding ${body.take(100).toList()}:\n$e\n$st',
        );
      }
    }
  });
}
