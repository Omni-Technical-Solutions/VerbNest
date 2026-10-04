import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'byte_reader.dart';
import 'errors.dart';
import 'models.dart';

/// Lets callers abort an in-flight request (FR-HTTP-009).
class CancelToken {
  final List<void Function()> _listeners = [];
  bool _cancelled = false;

  bool get isCancelled => _cancelled;

  void cancel() {
    if (_cancelled) return;
    _cancelled = true;
    for (final l in _listeners.toList()) {
      l();
    }
  }

  void _listen(void Function() l) {
    _listeners.add(l);
    if (_cancelled) l();
  }

  void _unlisten(void Function() l) => _listeners.remove(l);
}

/// HTTP/1.1 client over raw sockets so header order, casing and raw bytes
/// are under PostIt's control (architecture §3.1). Each exchange uses its own
/// connection (`Connection: close`); pooling is a later optimisation.
class HttpEngine {
  HttpEngine({this.userAgent = 'PostIt/0.1'});

  final String userAgent;

  Future<HttpResponseRecord> send(
    HttpRequestSpec spec, {
    CancelToken? cancel,
  }) async {
    final token = cancel ?? CancelToken();
    final hops = <HttpResponseRecord>[];
    var current = spec;
    while (true) {
      final response = await _exchange(current, token);
      final next = _nextHop(current, response);
      if (next == null) return _withRedirects(response, hops);
      if (hops.length >= spec.settings.maxRedirects) {
        throw TooManyRedirectsError(spec.settings.maxRedirects);
      }
      hops.add(response);
      current = next;
    }
  }

  HttpResponseRecord _withRedirects(
    HttpResponseRecord r,
    List<HttpResponseRecord> hops,
  ) {
    if (hops.isEmpty) return r;
    return HttpResponseRecord(
      status: r.status,
      reason: r.reason,
      httpVersion: r.httpVersion,
      headers: r.headers,
      body: r.body,
      wireBodySize: r.wireBodySize,
      timings: r.timings,
      finalUrl: r.finalUrl,
      sent: r.sent,
      redirects: List.unmodifiable(hops),
    );
  }

  HttpRequestSpec? _nextHop(HttpRequestSpec spec, HttpResponseRecord r) {
    final s = spec.settings;
    if (!s.followRedirects ||
        !const {301, 302, 303, 307, 308}.contains(r.status)) {
      return null;
    }
    final location = r.header('location');
    if (location == null) return null;
    final target = spec.url.resolve(location);
    final switchToGet =
        !s.keepMethodOnRedirect &&
        (r.status == 303 ||
            ((r.status == 301 || r.status == 302) && spec.method != 'HEAD'));
    final crossOrigin = _origin(target) != _origin(spec.url);
    final stripped = crossOrigin && s.stripAuthCrossOrigin;
    return HttpRequestSpec(
      method: switchToGet ? 'GET' : spec.method,
      url: target,
      headers: [
        for (final h in spec.headers)
          if (!_dropOnRedirect(h.$1, switchToGet, stripped)) h,
      ],
      body: switchToGet ? null : spec.body,
      settings: s,
    );
  }

  bool _dropOnRedirect(String name, bool switchToGet, bool stripAuth) {
    final n = name.toLowerCase();
    if (n == 'host') return true;
    if (switchToGet && (n == 'content-length' || n == 'content-type')) {
      return true;
    }
    return stripAuth && (n == 'authorization' || n == 'cookie');
  }

  String _origin(Uri u) => '${u.scheme}://${u.host}:${u.port}';

  Future<HttpResponseRecord> _exchange(
    HttpRequestSpec spec,
    CancelToken token,
  ) async {
    final conn = _Connection(spec, token);
    try {
      return await conn.run(_buildRequest(spec), userAgent);
    } finally {
      conn.dispose();
    }
  }

  _Wire _buildRequest(HttpRequestSpec spec) {
    final body = Uint8List.fromList(spec.body ?? const []);
    final headers = _withAutoHeaders(spec, body.length);
    final target = spec.url.hasQuery
        ? '${spec.url.path.isEmpty ? '/' : spec.url.path}?${spec.url.query}'
        : (spec.url.path.isEmpty ? '/' : spec.url.path);
    final head = StringBuffer('${spec.method} $target HTTP/1.1\r\n');
    for (final (k, v) in headers) {
      head.write('$k: $v\r\n');
    }
    head.write('\r\n');
    return _Wire(head.toString(), body);
  }

  List<Header> _withAutoHeaders(HttpRequestSpec spec, int bodyLength) {
    final user = spec.headers;
    bool has(String n) => user.any((h) => h.$1.toLowerCase() == n);
    final u = spec.url;
    final defaultPort = u.scheme == 'https' ? 443 : 80;
    final hostValue = u.hasPort && u.port != defaultPort
        ? '${u.host.contains(':') ? '[${u.host}]' : u.host}:${u.port}'
        : (u.host.contains(':') ? '[${u.host}]' : u.host);
    return [
      ...user,
      if (!has('host')) ('Host', hostValue),
      if (!has('user-agent')) ('User-Agent', userAgent),
      if (!has('accept')) ('Accept', '*/*'),
      if (!has('accept-encoding') && spec.settings.autoDecompress)
        ('Accept-Encoding', 'gzip, deflate'),
      if (!has('content-length') &&
          (bodyLength > 0 ||
              const {'POST', 'PUT', 'PATCH'}.contains(spec.method)))
        ('Content-Length', '$bodyLength'),
      if (!has('connection')) ('Connection', 'close'),
    ];
  }
}

class _Wire {
  _Wire(this.head, this.body);

  final String head;
  final Uint8List body;
}

/// One TCP/TLS connection and the request/response on it.
class _Connection {
  _Connection(this.spec, this.token);

  final HttpRequestSpec spec;
  final CancelToken token;
  Socket? _socket;
  Timer? _timer;
  bool _timedOut = false;
  void _onCancel() => _socket?.destroy();

  Future<HttpResponseRecord> run(_Wire wire, String userAgent) async {
    final sw = Stopwatch()..start();
    token._listen(_onCancel);
    _timer = Timer(spec.settings.timeout, () {
      _timedOut = true;
      _socket?.destroy();
    });
    try {
      return await _roundTrip(wire, sw);
    } catch (e) {
      throw _translate(e);
    }
  }

  void dispose() {
    _timer?.cancel();
    token._unlisten(_onCancel);
    _socket?.destroy();
  }

  Future<HttpResponseRecord> _roundTrip(_Wire wire, Stopwatch sw) async {
    final u = spec.url;
    if (u.host.isEmpty || (u.scheme != 'http' && u.scheme != 'https')) {
      throw ProtocolError('Unsupported URL: $u');
    }
    final port = u.hasPort ? u.port : (u.scheme == 'https' ? 443 : 80);

    var mark = sw.elapsed;
    final addresses = await InternetAddress.lookup(u.host);
    final dns = sw.elapsed - mark;
    _checkCancelled();

    mark = sw.elapsed;
    var socket = await Socket.connect(addresses.first, port);
    _socket = socket;
    final connect = sw.elapsed - mark;
    _checkCancelled();

    mark = sw.elapsed;
    if (u.scheme == 'https') {
      socket = await SecureSocket.secure(
        socket,
        host: u.host,
        supportedProtocols: const ['http/1.1'],
        onBadCertificate: spec.settings.verifyTls ? null : (_) => true,
      );
      _socket = socket;
    }
    final tls = sw.elapsed - mark;

    socket.add(utf8.encode(wire.head));
    if (wire.body.isNotEmpty) socket.add(wire.body);
    await socket.flush();
    final sentAt = sw.elapsed;

    final reader = ByteReader(socket);
    final parsed = await _readResponse(reader, sw, sentAt);
    return _record(parsed, wire, dns, connect, tls, sw);
  }

  void _checkCancelled() {
    if (token.isCancelled) throw const CancelledError();
  }

  Future<_Parsed> _readResponse(
    ByteReader reader,
    Stopwatch sw,
    Duration sentAt,
  ) async {
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
    final body = await _readBody(reader, headers, code);
    return _Parsed(
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
  ) async {
    String? h(String n) {
      for (final (k, v) in headers) {
        if (k.toLowerCase() == n) return v;
      }
      return null;
    }

    final noBody =
        spec.method == 'HEAD' ||
        status == 204 ||
        status == 304 ||
        (status >= 100 && status < 200);
    if (noBody) return Uint8List(0);
    if (h('transfer-encoding')?.toLowerCase().contains('chunked') ?? false) {
      return _readChunked(reader);
    }
    final length = int.tryParse(h('content-length') ?? '');
    return length != null ? reader.readExact(length) : reader.readToEnd();
  }

  Future<Uint8List> _readChunked(ByteReader reader) async {
    final out = BytesBuilder(copy: false);
    while (true) {
      final size = int.parse(
        (await reader.readLine()).split(';').first.trim(),
        radix: 16,
      );
      if (size == 0) {
        while ((await reader.readLine()).isNotEmpty) {}
        return out.toBytes();
      }
      out.add(await reader.readExact(size));
      await reader.readLine();
    }
  }

  HttpResponseRecord _record(
    _Parsed p,
    _Wire wire,
    Duration dns,
    Duration connect,
    Duration tls,
    Stopwatch sw,
  ) {
    final decoded = spec.settings.autoDecompress ? _decode(p) : p.body;
    return HttpResponseRecord(
      status: p.status,
      reason: p.reason,
      httpVersion: p.httpVersion,
      headers: p.headers,
      body: decoded,
      wireBodySize: p.body.length,
      timings: Timings(
        dns: dns,
        connect: connect,
        tls: tls,
        ttfb: p.ttfb,
        download: p.download,
        total: sw.elapsed,
      ),
      finalUrl: spec.url,
      sent: SentRequest(head: wire.head, body: wire.body, url: spec.url),
    );
  }

  Uint8List _decode(_Parsed p) {
    String? encoding;
    for (final (k, v) in p.headers) {
      if (k.toLowerCase() == 'content-encoding') encoding = v.toLowerCase();
    }
    try {
      return switch (encoding) {
        'gzip' || 'x-gzip' => Uint8List.fromList(gzip.decode(p.body)),
        'deflate' => Uint8List.fromList(zlib.decode(p.body)),
        _ => p.body,
      };
    } on FormatException catch (e) {
      throw ProtocolError('Could not decode $encoding body: ${e.message}');
    }
  }

  HttpEngineError _translate(Object e) {
    // Destroying the socket makes the read fail with an unrelated error, so
    // cancel and timeout take precedence over whatever surfaced.
    if (token.isCancelled) return const CancelledError();
    if (_timedOut) {
      return TimeoutError(
        'Timed out after ${spec.settings.timeout.inMilliseconds} ms',
      );
    }
    if (e is HttpEngineError) return e;
    if (e is HandshakeException || e is TlsException) {
      return TlsError(
        'TLS error: $e. Disable certificate verification to proceed anyway.',
      );
    }
    if (e is SocketException) return NetworkError(e.message);
    if (e is FormatException) return NetworkError(e.message);
    return NetworkError('$e');
  }
}

class _Parsed {
  _Parsed({
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
