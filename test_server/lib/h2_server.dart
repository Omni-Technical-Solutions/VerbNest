import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:http2/transport.dart' as h2;

import 'test_server.dart';

/// What an HTTP/2 client sent, with header names as received (lower case).
class H2Request {
  H2Request(this.method, this.path, this.authority, this.headers, this.body);

  final String method;
  final String path;
  final String authority;
  final List<(String, String)> headers;
  final Uint8List body;
}

/// A TLS listener that speaks only HTTP/2 (ALPN `h2`), for engine tests.
/// Routes: `/echo` (JSON of the request), `/status/N`, `/gzip`, `/trailers`
/// (headers, body, then trailers) and `/large/N` (N MiB).
class H2TestServer {
  H2TestServer._(this._server);

  final SecureServerSocket _server;
  final List<H2Request> requests = [];
  final Set<Socket> _sockets = {};

  /// Connections accepted so far.
  int connections = 0;

  int get port => _server.port;
  String get baseUrl => 'https://127.0.0.1:$port';

  static Future<H2TestServer> start() async {
    final (cert, key) = await TestServer.selfSignedCertificate();
    final context = SecurityContext()
      ..useCertificateChainBytes(cert)
      ..usePrivateKeyBytes(key)
      ..setAlpnProtocols(['h2'], true);
    final server = await SecureServerSocket.bind(
      InternetAddress.loopbackIPv4,
      0,
      context,
    );
    final ts = H2TestServer._(server);
    server.listen(ts._onSocket, onError: (Object _) {});
    return ts;
  }

  Future<void> close() async {
    await _server.close();
    for (final s in _sockets.toList()) {
      s.destroy();
    }
  }

  void _onSocket(SecureSocket socket) {
    connections++;
    _sockets.add(socket);
    final conn = h2.ServerTransportConnection.viaSocket(socket);
    conn.incomingStreams.listen(
      (stream) => unawaited(_serve(stream)),
      onError: (Object _) => socket.destroy(),
      onDone: () => _sockets.remove(socket),
    );
  }

  Future<void> _serve(h2.ServerTransportStream stream) async {
    final headers = <(String, String)>[];
    final body = BytesBuilder(copy: false);
    await for (final m in stream.incomingMessages) {
      if (m is h2.HeadersStreamMessage) {
        for (final h in m.headers) {
          headers.add((utf8.decode(h.name), utf8.decode(h.value)));
        }
      } else if (m is h2.DataStreamMessage) {
        body.add(m.bytes);
      }
    }
    String pseudo(String n) =>
        headers.where((h) => h.$1 == n).map((h) => h.$2).firstOrNull ?? '';
    final req = H2Request(
      pseudo(':method'),
      pseudo(':path'),
      pseudo(':authority'),
      [
        for (final h in headers)
          if (!h.$1.startsWith(':')) h,
      ],
      body.toBytes(),
    );
    requests.add(req);

    final uri = Uri.parse(req.path);
    final seg = uri.pathSegments;
    void reply(
      int status,
      List<int> bytes, [
      List<(String, String)> extra = const [],
    ]) {
      stream.sendHeaders([
        h2.Header.ascii(':status', '$status'),
        h2.Header.ascii('content-length', '${bytes.length}'),
        for (final (k, v) in extra) h2.Header.ascii(k, v),
      ]);
      // One large message stalls once the peer's flow-control window is used
      // up, so send it in frame-sized pieces.
      const piece = 16 * 1024;
      for (var i = 0; i < bytes.length; i += piece) {
        stream.sendData(bytes.sublist(i, min(i + piece, bytes.length)));
      }
      stream.sendData(const [], endStream: true);
    }

    switch (seg.firstOrNull) {
      case 'echo':
        reply(
          200,
          utf8.encode(
            jsonEncode({
              'method': req.method,
              'path': uri.path,
              'query': uri.query,
              'authority': req.authority,
              'headers': [
                for (final (k, v) in req.headers) [k, v],
              ],
              'bodyBase64': base64Encode(req.body),
            }),
          ),
          [('content-type', 'application/json')],
        );
      case 'status':
        final code = int.tryParse(seg.length > 1 ? seg[1] : '') ?? 400;
        reply(code, utf8.encode('status $code'));
      case 'gzip':
        reply(200, gzip.encode(utf8.encode('gzipped body')), [
          ('content-encoding', 'gzip'),
        ]);
      case 'trailers':
        stream.sendHeaders([h2.Header.ascii(':status', '200')]);
        stream.sendData(utf8.encode('with trailers'));
        stream.sendHeaders([
          h2.Header.ascii('x-trailer', '1'),
        ], endStream: true);
      case 'kb':
        final kb = int.tryParse(seg.length > 1 ? seg[1] : '') ?? 1;
        reply(200, Uint8List(kb * 1024));
      case 'large':
        final mb = int.tryParse(seg.length > 1 ? seg[1] : '') ?? 1;
        reply(200, Uint8List(mb * 1024 * 1024));
      default:
        reply(404, utf8.encode('not found'));
    }
  }
}
