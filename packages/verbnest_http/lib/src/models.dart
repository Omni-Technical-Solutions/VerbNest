import 'dart:convert';
import 'dart:io' show Platform;
import 'dart:typed_data';

import 'proxy.dart';
import 'tls_config.dart';

typedef Header = (String name, String value);

/// What the user asked to send, after variable resolution.
class HttpRequestSpec {
  HttpRequestSpec({
    required this.method,
    required this.url,
    this.headers = const [],
    this.body,
    this.settings = const HttpSettings(),
  });

  final String method;
  final Uri url;

  /// Order and casing are preserved on the wire (constitution V).
  final List<Header> headers;
  final List<int>? body;
  final HttpSettings settings;
}

/// Which HTTP version to offer (FR-HTTP-007). HTTP/2 needs `https://`.
enum HttpVersionPref {
  /// Offer both through ALPN and use what the server picks.
  auto,
  http1,
  http2;

  /// The stored form: `auto`, `1.1` or `2`.
  String get code => switch (this) {
    auto => 'auto',
    http1 => '1.1',
    http2 => '2',
  };

  static HttpVersionPref fromCode(String? code) => switch (code) {
    '1.1' => http1,
    '2' => http2,
    _ => auto,
  };
}

/// Largest response body read from the wire, and the largest after
/// decompression, on a computer and on a phone or tablet (which the operating
/// system ends the app for long before). Bodies are held in memory, then
/// formatted and searched, so a hostile or mistaken server must not be able to
/// ask for more (security review S4).
const desktopMaxBodyBytes = 256 * 1024 * 1024;
const mobileMaxBodyBytes = 64 * 1024 * 1024;

final int maxBodyBytes = Platform.isAndroid || Platform.isIOS
    ? mobileMaxBodyBytes
    : desktopMaxBodyBytes;

class HttpSettings {
  const HttpSettings({
    this.httpVersion = HttpVersionPref.auto,
    this.timeout = const Duration(seconds: 30),
    this.followRedirects = true,
    this.maxRedirects = 10,
    this.verifyTls = true,
    this.autoDecompress = true,
    this.keepMethodOnRedirect = false,
    this.stripAuthCrossOrigin = true,
    this.sendCookies = true,
    this.proxy,
    this.useSystemProxy = false,
    this.tls,
  });

  final HttpVersionPref httpVersion;
  final Duration timeout;
  final bool followRedirects;
  final int maxRedirects;
  final bool verifyTls;
  final bool autoDecompress;

  /// Keep the original method/body on 301/302/303 instead of switching to GET.
  final bool keepMethodOnRedirect;

  /// Drop `Authorization` and `Cookie` when a redirect leaves the origin.
  final bool stripAuthCrossOrigin;

  /// Use the engine's cookie jar for this request (FR-HTTP-011).
  final bool sendCookies;

  /// A manual proxy; null sends directly (FR-HTTP-012).
  final ProxyConfig? proxy;

  /// Take the proxy from `HTTP_PROXY`/`HTTPS_PROXY`/`NO_PROXY` when [proxy]
  /// is not set.
  final bool useSystemProxy;

  /// Extra CA and client certificates (FR-HTTP-013).
  final TlsConfig? tls;
}

class Timings {
  const Timings({
    required this.dns,
    required this.connect,
    required this.tls,
    required this.ttfb,
    required this.download,
    required this.total,
  });

  final Duration dns;
  final Duration connect;
  final Duration tls;
  final Duration ttfb;
  final Duration download;
  final Duration total;
}

/// The exact bytes written for one request/response exchange (FR-HTTP-010).
class SentRequest {
  const SentRequest({
    required this.head,
    required this.body,
    required this.url,
  });

  final String head;
  final Uint8List body;
  final Uri url;
}

class HttpResponseRecord {
  HttpResponseRecord({
    required this.status,
    required this.reason,
    required this.httpVersion,
    required this.headers,
    required this.body,
    required this.wireBodySize,
    required this.timings,
    required this.finalUrl,
    required this.sent,
    this.redirects = const [],
    this.tls,
  });

  final int status;
  final String reason;
  final String httpVersion;
  final List<Header> headers;

  /// Body after content-encoding was removed (when auto-decompress is on).
  final Uint8List body;

  /// Body bytes as received, before decoding.
  final int wireBodySize;
  final Timings timings;
  final Uri finalUrl;

  /// The request that produced this response (last hop).
  final SentRequest sent;

  /// Earlier hops that returned redirects, oldest first.
  final List<HttpResponseRecord> redirects;

  /// The server certificate for HTTPS exchanges.
  final TlsInfo? tls;

  String? header(String name) {
    final lower = name.toLowerCase();
    for (final (k, v) in headers) {
      if (k.toLowerCase() == lower) return v;
    }
    return null;
  }

  /// Decoded once; large bodies are read several times per screen update.
  late final String bodyText = utf8.decode(body, allowMalformed: true);
}
