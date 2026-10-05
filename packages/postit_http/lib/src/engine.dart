import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:postit_core/postit_core.dart' show CookieJar;

import 'byte_reader.dart';
import 'errors.dart';
import 'models.dart';
import 'proxy.dart';
import 'tls_config.dart';

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
  HttpEngine({this.userAgent = 'PostIt/0.1', this.cookieJar, this.environment});

  final String userAgent;

  /// Cookies are stored from responses and sent automatically while this is
  /// set and the request allows it (FR-HTTP-011).
  final CookieJar? cookieJar;

  /// Variables read for the system proxy; defaults to the process environment.
  final Map<String, String>? environment;

  Future<HttpResponseRecord> send(
    HttpRequestSpec spec, {
    CancelToken? cancel,
  }) async {
    final token = cancel ?? CancelToken();
    final hops = <HttpResponseRecord>[];
    var current = spec;
    while (true) {
      final sending = _withCookies(current);
      final response = await _exchange(sending, token);
      _storeCookies(current, response);
      final next = _nextHop(current, response);
      if (next == null) return _withRedirects(response, hops);
      if (hops.length >= spec.settings.maxRedirects) {
        throw TooManyRedirectsError(spec.settings.maxRedirects);
      }
      hops.add(response);
      current = next;
    }
  }

  HttpRequestSpec _withCookies(HttpRequestSpec spec) {
    final jar = cookieJar;
    if (jar == null || !spec.settings.sendCookies) return spec;
    if (spec.headers.any((h) => h.$1.toLowerCase() == 'cookie')) return spec;
    final value = jar.cookieHeader(spec.url);
    if (value == null) return spec;
    return HttpRequestSpec(
      method: spec.method,
      url: spec.url,
      headers: [...spec.headers, ('Cookie', value)],
      body: spec.body,
      settings: spec.settings,
    );
  }

  void _storeCookies(HttpRequestSpec spec, HttpResponseRecord r) {
    final jar = cookieJar;
    if (jar == null || !spec.settings.sendCookies) return;
    jar.storeFromResponse(spec.url, [
      for (final (k, v) in r.headers)
        if (k.toLowerCase() == 'set-cookie') v,
    ]);
  }

  ProxyConfig? _proxyFor(HttpRequestSpec spec) {
    final s = spec.settings;
    final manual = s.proxy;
    if (manual != null) return manual.bypasses(spec.url.host) ? null : manual;
    if (!s.useSystemProxy) return null;
    return ProxyConfig.fromEnvironment(
      spec.url,
      environment ?? Platform.environment,
    );
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
      tls: r.tls,
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
    return stripAuth && _looksLikeCredential(n);
  }

  /// Names such as `x-api-key` or `x-auth-token` carry secrets just like
  /// `authorization`, so they must not follow a redirect to another origin.
  static final _credentialName = RegExp(
    r'auth|token|secret|api[-_]?key|password|credential|session|cookie',
  );

  bool _looksLikeCredential(String lowerName) =>
      _credentialName.hasMatch(lowerName);

  String _origin(Uri u) => '${u.scheme}://${u.host}:${u.port}';

  Future<HttpResponseRecord> _exchange(
    HttpRequestSpec spec,
    CancelToken token,
  ) async {
    final proxy = _proxyFor(spec);
    final conn = _Connection(spec, token, proxy);
    try {
      return await conn.run(
        _buildRequest(
          spec,
          absoluteForm:
              proxy != null &&
              proxy.kind == ProxyKind.http &&
              spec.url.scheme == 'http',
          proxy: proxy,
        ),
        userAgent,
      );
    } finally {
      conn.dispose();
    }
  }

  _Wire _buildRequest(
    HttpRequestSpec spec, {
    bool absoluteForm = false,
    ProxyConfig? proxy,
  }) {
    final body = Uint8List.fromList(spec.body ?? const []);
    final headers = _withAutoHeaders(spec, body.length);
    if (absoluteForm &&
        proxy!.hasAuth &&
        !headers.any((h) => h.$1.toLowerCase() == 'proxy-authorization')) {
      headers.add(('Proxy-Authorization', _basic(proxy)));
    }
    final target = absoluteForm
        ? spec.url.removeFragment().toString()
        : spec.url.hasQuery
        ? '${spec.url.path.isEmpty ? '/' : spec.url.path}?${spec.url.query}'
        : (spec.url.path.isEmpty ? '/' : spec.url.path);
    final head = StringBuffer('${spec.method} $target HTTP/1.1\r\n');
    for (final (k, v) in headers) {
      head.write('$k: $v\r\n');
    }
    head.write('\r\n');
    return _Wire(head.toString(), body);
  }

  static String _basic(ProxyConfig p) =>
      'Basic ${base64Encode(utf8.encode('${p.username}:${p.password}'))}';

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
  _Connection(this.spec, this.token, this.proxy);

  final HttpRequestSpec spec;
  final CancelToken token;
  final ProxyConfig? proxy;
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

    final via = proxy;
    var mark = sw.elapsed;
    final addresses = await InternetAddress.lookup(via?.host ?? u.host);
    final dns = sw.elapsed - mark;
    _checkCancelled();

    mark = sw.elapsed;
    var socket = await Socket.connect(addresses.first, via?.port ?? port);
    _socket = socket;
    ByteReader? reader;
    if (via != null) {
      if (via.kind == ProxyKind.socks5) {
        reader = ByteReader(socket);
        await _socks5(socket, reader, via, u.host, port);
      } else if (u.scheme == 'https') {
        reader = ByteReader(socket);
        await _httpConnect(socket, reader, via, u.host, port);
      }
    }
    final connect = sw.elapsed - mark;
    _checkCancelled();

    mark = sw.elapsed;
    TlsInfo? tlsInfo;
    if (u.scheme == 'https') {
      final config = spec.settings.tls;
      SecurityContext? context;
      if (config != null && !config.isEmpty) {
        try {
          context = config.contextFor(u.host);
        } on Object catch (e) {
          throw TlsError('Could not load the certificates: $e');
        }
      }
      final secure = await SecureSocket.secure(
        socket,
        host: u.host,
        context: context,
        supportedProtocols: const ['http/1.1'],
        onBadCertificate: spec.settings.verifyTls ? null : (_) => true,
      );
      socket = secure;
      _socket = socket;
      reader = null;
      final cert = secure.peerCertificate;
      if (cert != null) {
        tlsInfo = TlsInfo(
          subject: cert.subject,
          issuer: cert.issuer,
          validFrom: cert.startValidity,
          validTo: cert.endValidity,
          protocol: secure.selectedProtocol,
          clientCertificateSent:
              config?.clientCertificates.any((c) => c.matches(u.host)) ?? false,
        );
      }
    }
    final tls = sw.elapsed - mark;

    socket.add(utf8.encode(wire.head));
    if (wire.body.isNotEmpty) socket.add(wire.body);
    await socket.flush();
    final sentAt = sw.elapsed;

    reader ??= ByteReader(socket);
    final parsed = await _readResponse(reader, sw, sentAt);
    return _record(parsed, wire, dns, connect, tls, sw, tlsInfo);
  }

  static String _hostPort(String host, int port) =>
      '${host.contains(':') ? '[$host]' : host}:$port';

  /// Opens a tunnel through an HTTP proxy with CONNECT.
  Future<void> _httpConnect(
    Socket socket,
    ByteReader reader,
    ProxyConfig proxy,
    String host,
    int port,
  ) async {
    final hp = _hostPort(host, port);
    socket.add(
      utf8.encode(
        'CONNECT $hp HTTP/1.1\r\nHost: $hp\r\n'
        '${proxy.hasAuth ? 'Proxy-Authorization: ${HttpEngine._basic(proxy)}\r\n' : ''}'
        '\r\n',
      ),
    );
    await socket.flush();
    final head = await reader.readHead();
    if (head == null) {
      throw const NetworkError('The proxy closed the connection');
    }
    final line = latin1.decode(head).split('\r\n').first;
    final parts = line.split(' ');
    final code = parts.length > 1 ? int.tryParse(parts[1]) : null;
    if (code == null || code < 200 || code >= 300) {
      throw NetworkError('The proxy refused the tunnel: $line');
    }
  }

  /// SOCKS5 handshake (RFC 1928, user/password per RFC 1929). The proxy
  /// resolves [host], so DNS does not leak.
  Future<void> _socks5(
    Socket socket,
    ByteReader reader,
    ProxyConfig proxy,
    String host,
    int port,
  ) async {
    socket.add(proxy.hasAuth ? [5, 2, 0, 2] : [5, 1, 0]);
    await socket.flush();
    final choice = await reader.readExact(2);
    if (choice[0] != 5) throw const NetworkError('Not a SOCKS5 proxy');
    if (choice[1] == 0xFF) {
      throw const NetworkError(
        'The SOCKS5 proxy accepts none of our log-in methods',
      );
    }
    if (choice[1] == 2) {
      if (!proxy.hasAuth) {
        throw const NetworkError(
          'The SOCKS5 proxy needs a user name and password',
        );
      }
      final user = utf8.encode(proxy.username);
      final pass = utf8.encode(proxy.password);
      if (user.length > 255 || pass.length > 255) {
        throw const NetworkError('The proxy user name or password is too long');
      }
      socket.add([1, user.length, ...user, pass.length, ...pass]);
      await socket.flush();
      final ok = await reader.readExact(2);
      if (ok[1] != 0) {
        throw const NetworkError(
          'The SOCKS5 proxy rejected the user name or password',
        );
      }
    }
    final ip = InternetAddress.tryParse(host);
    final addr = ip != null
        ? [ip.type == InternetAddressType.IPv4 ? 1 : 4, ...ip.rawAddress]
        : [3, utf8.encode(host).length, ...utf8.encode(host)];
    if (ip == null && utf8.encode(host).length > 255) {
      throw const NetworkError('The host name is too long for SOCKS5');
    }
    socket.add([5, 1, 0, ...addr, port >> 8, port & 0xFF]);
    await socket.flush();
    final reply = await reader.readExact(4);
    if (reply[1] != 0) {
      const reasons = {
        1: 'general failure',
        2: 'not allowed by the proxy rules',
        3: 'network unreachable',
        4: 'host unreachable',
        5: 'connection refused',
        6: 'TTL expired',
        7: 'command not supported',
        8: 'address type not supported',
      };
      throw NetworkError(
        'The SOCKS5 proxy could not connect: ${reasons[reply[1]] ?? 'error ${reply[1]}'}',
      );
    }
    final skip = switch (reply[3]) {
      1 => 4,
      4 => 16,
      3 => (await reader.readExact(1))[0],
      _ => throw const NetworkError('Unexpected SOCKS5 reply'),
    };
    await reader.readExact(skip + 2);
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
    TlsInfo? tlsInfo,
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
      tls: tlsInfo,
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
