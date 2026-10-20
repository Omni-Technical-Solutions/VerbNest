import 'dart:convert';
import 'dart:io' show Platform;

import 'package:test/test.dart';
import 'package:verbnest_http/src/byte_reader.dart';
import 'package:verbnest_http/src/errors.dart';
import 'package:verbnest_http/src/models.dart';
import 'package:verbnest_http/src/response_reader.dart';

/// A server must not be able to make the app hold more than a phone or a
/// computer can reasonably show (security review S4).
void main() {
  test('the limit is smaller on a phone than on a computer', () {
    expect(mobileMaxBodyBytes, lessThan(desktopMaxBodyBytes));
    expect(mobileMaxBodyBytes, 64 * 1024 * 1024);
    expect(desktopMaxBodyBytes, 256 * 1024 * 1024);
    expect(
      maxBodyBytes,
      Platform.isAndroid || Platform.isIOS
          ? mobileMaxBodyBytes
          : desktopMaxBodyBytes,
    );
  });

  test(
    'a Content-Length over the limit is refused before any body is read',
    () {
      final head = latin1.encode(
        'HTTP/1.1 200 OK\r\nContent-Length: ${maxBodyBytes + 1}\r\n\r\n',
      );
      expect(
        readResponse(
          ByteReader(Stream.value(head)),
          Stopwatch()..start(),
          Duration.zero,
          method: 'GET',
        ),
        throwsA(
          isA<ProtocolError>().having(
            (e) => e.message,
            'message',
            contains('MB'),
          ),
        ),
      );
    },
  );

  test('a chunk size over the limit is refused', () {
    final bytes = latin1.encode(
      'HTTP/1.1 200 OK\r\nTransfer-Encoding: chunked\r\n\r\n'
      '${(maxBodyBytes + 1).toRadixString(16)}\r\n',
    );
    expect(
      readResponse(
        ByteReader(Stream.value(bytes)),
        Stopwatch()..start(),
        Duration.zero,
        method: 'GET',
      ),
      throwsA(isA<ProtocolError>()),
    );
  });
}
