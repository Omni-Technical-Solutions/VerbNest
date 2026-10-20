import 'dart:convert';
import 'dart:io' show gzip, zlib;
import 'dart:typed_data';

import 'byte_reader.dart';
import 'errors.dart';
import 'models.dart';

/// Reads the status line, headers and body of one response from [reader].
/// [method] is the request's, because a HEAD response has no body.
Future<ParsedResponse> readResponse(
  ByteReader reader,
  Stopwatch sw,
  Duration sentAt, {
  required String method,
}) async {
  final head = await reader.readHead();
  if (head == null) {
    throw const NetworkError('Connection closed before a response arrived');
  }
  final ttfb = sw.elapsed - sentAt;
  final lines = latin1.decode(head).split('\r\n');
  final status = lines.first.split(' ');
  if (status.length < 2 || !status.first.startsWith('HTTP/')) {
    throw ProtocolError('Malformed status line: ${lines.first}');
  }
  final headers = <Header>[
    for (final line in lines.skip(1))
      if (line.contains(':'))
        (
          line.substring(0, line.indexOf(':')),
          line.substring(line.indexOf(':') + 1).trim(),
        ),
  ];
  final code = int.tryParse(status[1]);
  if (code == null) throw ProtocolError('Bad status code: ${status[1]}');
  final downloadStart = sw.elapsed;
  final body = await _readBody(reader, headers, code, method);
  return ParsedResponse(
    httpVersion: status.first.substring(5),
    status: code,
    reason: status.skip(2).join(' '),
    headers: headers,
    body: body,
    ttfb: ttfb,
    download: sw.elapsed - downloadStart,
  );
}

Future<Uint8List> _readBody(
  ByteReader reader,
  List<Header> headers,
  int status,
  String method,
) async {
  String? h(String n) {
    for (final (k, v) in headers) {
      if (k.toLowerCase() == n) return v;
    }
    return null;
  }

  final noBody =
      method == 'HEAD' ||
      status == 204 ||
      status == 304 ||
      (status >= 100 && status < 200);
  if (noBody) return Uint8List(0);
  if (h('transfer-encoding')?.toLowerCase().contains('chunked') ?? false) {
    return _readChunked(reader);
  }
  final length = int.tryParse(h('content-length') ?? '');
  if (length != null && length > maxBodyBytes) {
    throw const ProtocolError('Response body is too large');
  }
  return length != null
      ? reader.readExact(length)
      : reader.readToEnd(max: maxBodyBytes);
}

Future<Uint8List> _readChunked(ByteReader reader) async {
  final out = BytesBuilder(copy: false);
  while (true) {
    final size = int.parse(
      (await reader.readLine()).split(';').first.trim(),
      radix: 16,
    );
    if (size < 0 || out.length + size > maxBodyBytes) {
      throw const ProtocolError('Response body is too large');
    }
    if (size == 0) {
      while ((await reader.readLine()).isNotEmpty) {}
      return out.toBytes();
    }
    out.add(await reader.readExact(size));
    await reader.readLine();
  }
}

/// Undoes `Content-Encoding: gzip` or `deflate`, capped at [maxBodyBytes].
Uint8List decodeContentEncoding(List<Header> headers, Uint8List body) {
  String? encoding;
  for (final (k, v) in headers) {
    if (k.toLowerCase() == 'content-encoding') encoding = v.toLowerCase();
  }
  try {
    return switch (encoding) {
      'gzip' || 'x-gzip' => _inflate(gzip, body),
      'deflate' => _inflate(zlib, body),
      _ => body,
    };
  } on FormatException catch (e) {
    throw ProtocolError('Could not decode $encoding body: ${e.message}');
  }
}

/// Inflates in chunks so a small compressed body cannot expand past
/// [maxBodyBytes] in memory.
Uint8List _inflate(Codec<List<int>, List<int>> codec, Uint8List body) {
  final out = BytesBuilder(copy: false);
  final sink = codec.decoder.startChunkedConversion(
    ByteConversionSink.from(_CappedSink(out, maxBodyBytes)),
  );
  sink.add(body);
  sink.close();
  return out.toBytes();
}

/// One response as read from the wire, before the body is decompressed.
class ParsedResponse {
  ParsedResponse({
    required this.httpVersion,
    required this.status,
    required this.reason,
    required this.headers,
    required this.body,
    required this.ttfb,
    required this.download,
  });

  final String httpVersion;
  final int status;
  final String reason;
  final List<Header> headers;
  final Uint8List body;
  final Duration ttfb;
  final Duration download;
}

class _CappedSink implements Sink<List<int>> {
  _CappedSink(this._out, this._max);

  final BytesBuilder _out;
  final int _max;

  @override
  void add(List<int> chunk) {
    if (_out.length + chunk.length > _max) {
      throw const ProtocolError('Decompressed response body is too large');
    }
    _out.add(chunk);
  }

  @override
  void close() {}
}
