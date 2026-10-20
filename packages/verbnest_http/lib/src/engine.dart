import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:verbnest_core/verbnest_core.dart' show CookieJar;

import 'byte_reader.dart';
import 'errors.dart';
import 'http2_exchange.dart';
import 'models.dart';
import 'proxy.dart';
import 'proxy_tunnel.dart';
import 'redirects.dart';
import 'request_writer.dart';
import 'response_reader.dart';
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
/// are under VerbNest's control (architecture §3.1). Each exchange uses its own
/// connection (`Connection: close`); pooling is a later optimisation.
class HttpEngine {
  HttpEngine({
    this.userAgent = 'VerbNest/0.1',
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
      final next = nextHop(current, response);
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

  Future<HttpResponseRecord> _exchange(
    HttpRequestSpec spec,
    CancelToken token,
  ) async {
    final proxy = _proxyFor(spec);
    final conn = _Connection(spec, token, proxy);
    try {
      return await conn.run(
        buildWireRequest(
          spec,
          userAgent,
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

  Future<HttpResponseRecord> run(WireRequest wire, String userAgent) async {
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

  Future<HttpResponseRecord> _roundTrip(WireRequest wire, Stopwatch sw) async {
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
    final parsed = await readResponse(
      reader ?? ByteReader(socket),
      sw,
      sentAt,
      method: spec.method,
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
    WireRequest wire,
    Socket socket,
    Stopwatch sw,
    Duration dns,
    Duration connect,
    _Secured tls,
  ) async {
    final fields = h2Fields(wire.method, spec.url, wire.target, wire.headers);
    final h2Wire = WireRequest(
      h2HeadText(wire.method, fields),
      wire.body,
      wire.method,
      wire.target,
      wire.headers,
    );
    final r = await h2Exchange(socket, fields, wire.body, sw);
    final parsed = ParsedResponse(
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

  HttpResponseRecord _record(
    ParsedResponse p,
    WireRequest wire,
    Duration dns,
    Duration connect,
    Duration tls,
    Stopwatch sw,
    TlsInfo? tlsInfo,
  ) {
    final decoded = spec.settings.autoDecompress
        ? decodeContentEncoding(p.headers, p.body)
        : p.body;
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
