import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

/// A request exactly as received on the wire.
class RawRequest {
  RawRequest(this.method, this.target, this.headers, this.body);

  final String method;
  final String target;

  /// Header name/value pairs in received order and casing.
  final List<(String, String)> headers;
  final Uint8List body;

  Uri get uri => Uri.parse(target);

  String? header(String name) {
    final lower = name.toLowerCase();
    for (final (k, v) in headers) {
      if (k.toLowerCase() == lower) return v;
    }
    return null;
  }
}

/// Local HTTP/1.1 server used by every PostIt test (constitution X).
///
/// It parses requests itself instead of using `HttpServer`, because
/// `HttpServer` normalises header names and would hide wire-fidelity bugs.
class TestServer {
  TestServer._(this._server);

  final ServerSocket _server;
  final Set<Socket> _sockets = {};
  final List<RawRequest> requests = [];

  int get port => _server.port;
  String get baseUrl => 'http://127.0.0.1:$port';

  static Future<TestServer> start() async {
    final server = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
    final ts = TestServer._(server);
    server.listen(ts._onConnection);
    return ts;
  }

  Future<void> close() async {
    await _server.close();
    for (final s in _sockets.toList()) {
      s.destroy();
    }
  }

  void _onConnection(Socket socket) {
    _sockets.add(socket);
    final parser = _RequestParser();
    final queue = StreamController<RawRequest>();
    socket.listen(
      (data) {
        parser.add(data);
        RawRequest? req;
        while ((req = parser.take()) != null) {
          queue.add(req!);
        }
      },
      onDone: () {
        queue.close();
        _sockets.remove(socket);
      },
      onError: (_) => socket.destroy(),
      cancelOnError: true,
    );
    unawaited(_serve(socket, queue.stream));
  }

  Future<void> _serve(Socket socket, Stream<RawRequest> reqs) async {
    try {
      await for (final req in reqs) {
        requests.add(req);
        final keepOpen = await _handle(socket, req);
        if (!keepOpen) break;
      }
    } on SocketException {
      // Client went away mid-response (e.g. cancel); nothing to do.
    } finally {
      await socket.close().catchError((_) {});
      _sockets.remove(socket);
    }
  }

  Future<bool> _handle(Socket socket, RawRequest req) async {
    final path = req.uri.path;
    final seg = path.split('/').where((s) => s.isNotEmpty).toList();
    final closeAfter = req.header('connection')?.toLowerCase() == 'close';
    final route = seg.isEmpty ? '' : seg.first;

    switch (route) {
      case 'echo':
        _write(socket, 200, _echoJson(req), closeAfter: closeAfter);
      case 'status':
        final code = int.tryParse(seg.length > 1 ? seg[1] : '') ?? 400;
        _write(
          socket,
          code,
          utf8.encode('status $code'),
          closeAfter: closeAfter,
        );
      case 'delay':
        final ms = int.tryParse(seg.length > 1 ? seg[1] : '') ?? 0;
        await Future<void>.delayed(Duration(milliseconds: ms));
        _write(socket, 200, utf8.encode('delayed $ms'), closeAfter: closeAfter);
      case 'redirect':
        _redirect(socket, seg, closeAfter);
      case 'gzip':
        _write(
          socket,
          200,
          gzip.encode(utf8.encode('gzipped body')),
          extra: [('Content-Encoding', 'gzip')],
          closeAfter: closeAfter,
        );
      case 'chunked':
        await _chunked(socket);
      case 'large':
        final mb = int.tryParse(seg.length > 1 ? seg[1] : '') ?? 1;
        _write(
          socket,
          200,
          Uint8List(mb * 1024 * 1024),
          closeAfter: closeAfter,
        );
      default:
        _write(socket, 404, utf8.encode('not found'), closeAfter: closeAfter);
    }
    return !closeAfter;
  }

  List<int> _echoJson(RawRequest req) {
    final body = jsonEncode({
      'method': req.method,
      'path': req.uri.path,
      'query': req.uri.query,
      'headers': [
        for (final (k, v) in req.headers) [k, v],
      ],
      'bodyBase64': base64Encode(req.body),
    });
    return utf8.encode(body);
  }

  void _redirect(Socket socket, List<String> seg, bool closeAfter) {
    final n = int.tryParse(seg.length > 1 ? seg[1] : '') ?? 0;
    final next = n <= 1 ? '/echo' : '/redirect/${n - 1}';
    _write(
      socket,
      302,
      const [],
      extra: [('Location', next)],
      closeAfter: closeAfter,
    );
  }

  Future<void> _chunked(Socket socket) async {
    socket.write('HTTP/1.1 200 OK\r\nTransfer-Encoding: chunked\r\n\r\n');
    for (final part in ['hello ', 'chunked ', 'world']) {
      socket.write('${part.length.toRadixString(16)}\r\n$part\r\n');
      await socket.flush();
    }
    socket.write('0\r\n\r\n');
  }

  void _write(
    Socket socket,
    int status,
    List<int> body, {
    List<(String, String)> extra = const [],
    bool closeAfter = false,
  }) {
    final head = StringBuffer('HTTP/1.1 $status ${_reason(status)}\r\n')
      ..write('Content-Length: ${body.length}\r\n');
    for (final (k, v) in extra) {
      head.write('$k: $v\r\n');
    }
    if (closeAfter) head.write('Connection: close\r\n');
    head.write('\r\n');
    socket.add(utf8.encode(head.toString()));
    socket.add(body);
  }

  static String _reason(int code) => switch (code) {
    200 => 'OK',
    201 => 'Created',
    204 => 'No Content',
    302 => 'Found',
    400 => 'Bad Request',
    404 => 'Not Found',
    500 => 'Internal Server Error',
    _ => 'Status',
  };
}

/// Incremental HTTP/1.1 request parser that keeps header order and casing.
class _RequestParser {
  final BytesBuilder _buf = BytesBuilder();
  static final _crlfcrlf = [13, 10, 13, 10];

  void add(List<int> data) => _buf.add(data);

  RawRequest? take() {
    final bytes = _buf.toBytes();
    final end = _indexOf(bytes, _crlfcrlf);
    if (end == -1) return null;
    final head = latin1.decode(bytes.sublist(0, end)).split('\r\n');
    final parts = head.first.split(' ');
    final headers = <(String, String)>[];
    for (final line in head.skip(1)) {
      final i = line.indexOf(':');
      if (i > 0)
        headers.add((line.substring(0, i), line.substring(i + 1).trim()));
    }
    final bodyStart = end + 4;
    final body = _readBody(bytes, bodyStart, headers);
    if (body == null) return null;
    _buf.clear();
    _buf.add(bytes.sublist(body.$2));
    return RawRequest(parts[0], parts[1], headers, body.$1);
  }

  (Uint8List, int)? _readBody(
    Uint8List bytes,
    int start,
    List<(String, String)> headers,
  ) {
    String? find(String name) {
      for (final (k, v) in headers) {
        if (k.toLowerCase() == name) return v;
      }
      return null;
    }

    if (find('transfer-encoding')?.toLowerCase() == 'chunked') {
      return _readChunked(bytes, start);
    }
    final len = int.tryParse(find('content-length') ?? '0') ?? 0;
    if (bytes.length - start < len) return null;
    return (Uint8List.fromList(bytes.sublist(start, start + len)), start + len);
  }

  (Uint8List, int)? _readChunked(Uint8List bytes, int start) {
    final out = BytesBuilder();
    var pos = start;
    while (true) {
      final lineEnd = _indexOf(bytes, [13, 10], pos);
      if (lineEnd == -1) return null;
      final size = int.parse(
        latin1.decode(bytes.sublist(pos, lineEnd)).split(';').first.trim(),
        radix: 16,
      );
      pos = lineEnd + 2;
      if (size == 0) {
        return bytes.length - pos < 2 ? null : (out.toBytes(), pos + 2);
      }
      if (bytes.length - pos < size + 2) return null;
      out.add(bytes.sublist(pos, pos + size));
      pos += size + 2;
    }
  }

  static int _indexOf(Uint8List hay, List<int> needle, [int from = 0]) {
    for (var i = from; i <= hay.length - needle.length; i++) {
      var ok = true;
      for (var j = 0; j < needle.length; j++) {
        if (hay[i + j] != needle[j]) {
          ok = false;
          break;
        }
      }
      if (ok) return i;
    }
    return -1;
  }
}
