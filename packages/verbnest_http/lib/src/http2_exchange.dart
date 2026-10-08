import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:http2/transport.dart' as h2;

import 'errors.dart';
import 'models.dart';

/// A response read over HTTP/2, before content-encoding is removed.
class H2Response {
  H2Response({
    required this.status,
    required this.headers,
    required this.body,
    required this.ttfb,
    required this.download,
  });

  final int status;
  final List<Header> headers;
  final Uint8List body;
  final Duration ttfb;
  final Duration download;
}

/// Headers that belong to HTTP/1.1 connection handling and are forbidden in
/// HTTP/2 (RFC 9113 §8.2.2). `host` becomes `:authority`.
const _connectionSpecific = {
  'connection',
  'keep-alive',
  'proxy-connection',
  'transfer-encoding',
  'upgrade',
  'host',
};

/// The text shown as the "sent" head for an HTTP/2 request. HTTP/2 has no
/// textual head, so this lists the pseudo-headers and fields as encoded.
String h2HeadText(String method, List<Header> fields) {
  final b = StringBuffer(
    '$method ${fields.firstWhere((h) => h.$1 == ':path').$2} HTTP/2\r\n',
  );
  for (final (k, v) in fields) {
    b.write('$k: $v\r\n');
  }
  return b.toString();
}

/// Builds the lower-case header list for an HTTP/2 request from the
/// HTTP/1.1-style [headers] the engine prepared.
List<Header> h2Fields(
  String method,
  Uri url,
  String target,
  List<Header> headers,
) {
  String? authority;
  final rest = <Header>[];
  for (final (k, v) in headers) {
    final lower = k.toLowerCase();
    if (lower == 'host') authority = v;
    if (_connectionSpecific.contains(lower)) continue;
    rest.add((lower, v));
  }
  final defaultPort = url.scheme == 'https' ? 443 : 80;
  final host = url.host.contains(':') ? '[${url.host}]' : url.host;
  return [
    (':method', method),
    (':scheme', url.scheme),
    (
      ':authority',
      authority ??
          (url.hasPort && url.port != defaultPort ? '$host:${url.port}' : host),
    ),
    (':path', target),
    ...rest,
  ];
}

/// Sends one request on a TLS socket that negotiated `h2` and reads the
/// whole response. The caller owns the socket.
Future<H2Response> h2Exchange(
  Socket socket,
  List<Header> fields,
  Uint8List body,
  Stopwatch sw,
) async {
  final transport = h2.ClientTransportConnection.viaSocket(socket);
  try {
    final stream = transport.makeRequest([
      for (final (k, v) in fields) h2.Header(utf8.encode(k), utf8.encode(v)),
    ], endStream: body.isEmpty);
    if (body.isNotEmpty) stream.sendData(body, endStream: true);
    final sentAt = sw.elapsed;

    int? status;
    final headers = <Header>[];
    final data = BytesBuilder(copy: false);
    Duration? ttfb;
    Duration? downloadStart;
    await for (final m in stream.incomingMessages) {
      if (m is h2.HeadersStreamMessage) {
        if (status != null) continue; // trailers
        final block = [
          for (final h in m.headers)
            (utf8.decode(h.name), latin1.decode(h.value)),
        ];
        final code = int.tryParse(
          block.where((h) => h.$1 == ':status').firstOrNull?.$2 ?? '',
        );
        if (code == null) {
          throw const ProtocolError('HTTP/2 response without :status');
        }
        if (code >= 100 && code < 200) continue;
        status = code;
        headers.addAll(block.where((h) => !h.$1.startsWith(':')));
        ttfb = sw.elapsed - sentAt;
        downloadStart = sw.elapsed;
      } else if (m is h2.DataStreamMessage) {
        data.add(m.bytes);
        if (data.length > maxBodyBytes) {
          throw const ProtocolError('Response body is too large');
        }
      }
    }
    if (status == null) {
      throw const NetworkError('Connection closed before a response arrived');
    }
    return H2Response(
      status: status,
      headers: headers,
      body: data.toBytes(),
      ttfb: ttfb!,
      download: sw.elapsed - downloadStart!,
    );
  } finally {
    unawaited(transport.terminate().catchError((Object _) {}));
  }
}
