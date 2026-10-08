import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:verbnest_core/verbnest_core.dart' show CookieJar;

import 'byte_reader.dart';
import 'errors.dart';
import 'http2_exchange.dart';
import 'models.dart';
import 'proxy.dart';
import 'proxy_tunnel.dart';
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
/// are under Verbnest's control (architecture §3.1). Each exchange uses its own
/// connection (`Connection: close`); pooling is a later optimisation.
class HttpEngine {
  HttpEngine({
    this.userAgent = 'Verbnest/0.1',
    this.cookieJar,
    this.environment,
  });

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
      headers.add(('Proxy-Authorization', basicProxyAuth(proxy)));
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
    return _Wire(head.toString(), body, spec.method, target, headers);
  }

  List<Header> _withAutoHeaders(HttpRequestSpec spec, int bodyLength) {
    final user = spec.headers;
    bool has(String n) => user.any((h) => h.$1.toLowerCase() == n);
    final u = spec.url;
    final defaultPort = u.scheme == 'https' ? 443 : 80;
    final hostValue = u.hasPort && u.port != defaultPort
        ? hostPort(u.host, u.port)
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
  _Wire(this.head, this.body, this.method, this.target, this.headers);

  final String head;
  final Uint8List body;
  final String method;
  final String target;
  final List<Header> headers;
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
    final wanted = spec.settings.httpVersion;
    if (wanted == HttpVersionPref.http2 && u.scheme != 'https') {
      throw const ProtocolError('HTTP/2 needs an https:// URL');
    }

    final dns = await _lookup(sw);
    final tcp = await _connectTcp(dns.address, sw);
    final tls = await _secure(tcp.socket, sw);
    final socket = tls.socket;

    if (tls.negotiated == 'h2') {
      return _exchangeH2(wire, socket, sw, dns.time, tcp.time, tls);
    }
    if (wanted == HttpVersionPref.http2) {
      throw const ProtocolError('The server does not support HTTP/2');
    }

    socket.add(utf8.encode(wire.head));
    if (wire.body.isNotEmpty) socket.add(wire.body);
    await socket.flush();
    final sentAt = sw.elapsed;

    // A TLS handshake consumed the reader that spoke to the proxy.
    final reader = tls.secured ? ByteReader(socket) : tcp.reader;
    final parsed = await _readResponse(
      reader ?? ByteReader(socket),
      sw,
      sentAt,
    );
    return _record(parsed, wire, dns.time, tcp.time, tls.time, sw, tls.info);
  }

  int get _port {
    final u = spec.url;
    return u.hasPort ? u.port : (u.scheme == 'https' ? 443 : 80);
  }

  Future<({InternetAddress address, Duration time})> _lookup(
    Stopwatch sw,
  ) async {
    final mark = sw.elapsed;
    final addresses = await InternetAddress.lookup(
      proxy?.host ?? spec.url.host,
    );
    final time = sw.elapsed - mark;
    _checkCancelled();
    return (address: addresses.first, time: time);
  }

  /// Opens the TCP connection, through the proxy tunnel when there is one.
  Future<({Socket socket, ByteReader? reader, Duration time})> _connectTcp(
    InternetAddress address,
    Stopwatch sw,
  ) async {
    final u = spec.url;
    final via = proxy;
    final mark = sw.elapsed;
    final socket = await Socket.connect(address, via?.port ?? _port);
    _socket = socket;
    ByteReader? reader;
    if (via != null) {
      if (via.kind == ProxyKind.socks5) {
        reader = ByteReader(socket);
        await socks5Handshake(socket, reader, via, u.host, _port);
      } else if (u.scheme == 'https') {
        reader = ByteReader(socket);
        await httpConnectTunnel(socket, reader, via, u.host, _port);
      }
    }
    final time = sw.elapsed - mark;
    _checkCancelled();
    return (socket: socket, reader: reader, time: time);
  }

  /// Upgrades [socket] to TLS for https URLs; other URLs pass through.
  Future<_Secured> _secure(Socket socket, Stopwatch sw) async {
    final u = spec.url;
    final mark = sw.elapsed;
    if (u.scheme != 'https') {
      return _Secured(socket, secured: false, time: sw.elapsed - mark);
    }
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
      supportedProtocols: switch (spec.settings.httpVersion) {
        HttpVersionPref.http1 => const ['http/1.1'],
        HttpVersionPref.http2 => const ['h2'],
        HttpVersionPref.auto => const ['h2', 'http/1.1'],
      },
      onBadCertificate: spec.settings.verifyTls ? null : (_) => true,
    );
    _socket = secure;
    final cert = secure.peerCertificate;
    return _Secured(
      secure,
      secured: true,
      negotiated: secure.selectedProtocol,
      time: sw.elapsed - mark,
      info: cert == null
          ? null
          : TlsInfo(
              subject: cert.subject,
              issuer: cert.issuer,
              validFrom: cert.startValidity,
              validTo: cert.endValidity,
              protocol: secure.selectedProtocol,
              clientCertificateSent:
                  config?.clientCertificates.any((c) => c.matches(u.host)) ??
                  false,
            ),
    );
  }

  Future<HttpResponseRecord> _exchangeH2(
    _Wire wire,
    Socket socket,
    Stopwatch sw,
    Duration dns,
    Duration connect,
    _Secured tls,
  ) async {
    final fields = h2Fields(wire.method, spec.url, wire.target, wire.headers);
    final h2Wire = _Wire(
      h2HeadText(wire.method, fields),
      wire.body,
      wire.method,
      wire.target,
      wire.headers,
    );
    final r = await h2Exchange(socket, fields, wire.body, sw);
    final parsed = _Parsed(
      httpVersion: '2',
      status: r.status,
      reason: '',
      headers: r.headers,
      body: r.body,
      ttfb: r.ttfb,
      download: r.download,
    );
    return _record(parsed, h2Wire, dns, connect, tls.time, sw, tls.info);
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

class _Secured {
  _Secured(
    this.socket, {
    required this.secured,
    required this.time,
    this.negotiated,
    this.info,
  });

  final Socket socket;
  final bool secured;
  final String? negotiated;
  final TlsInfo? info;
  final Duration time;
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
