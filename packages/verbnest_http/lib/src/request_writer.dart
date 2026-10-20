import 'dart:typed_data';

import 'errors.dart';
import 'models.dart';
import 'proxy.dart';
import 'proxy_tunnel.dart';

/// A request ready to write: head text, body and what it asks for.
class WireRequest {
  WireRequest(this.head, this.body, this.method, this.target, this.headers);

  final String head;
  final Uint8List body;
  final String method;
  final String target;
  final List<Header> headers;
}

/// Builds the HTTP/1.1 request head and body for [spec].
WireRequest buildWireRequest(
  HttpRequestSpec spec,
  String userAgent, {
  bool absoluteForm = false,
  ProxyConfig? proxy,
}) {
  final body = Uint8List.fromList(spec.body ?? const []);
  final headers = _withAutoHeaders(spec, body.length, userAgent);
  _rejectLineBreaks(spec, headers);
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
  return WireRequest(head.toString(), body, spec.method, target, headers);
}

/// A CR, LF or NUL in the method, URL or a header would split the request
/// on the wire and let one field forge others.
void _rejectLineBreaks(HttpRequestSpec spec, List<Header> headers) {
  final bad = RegExp(r'[\r\n\x00]');
  final fields = [spec.method, spec.url.toString()];
  for (final (k, v) in headers) {
    fields
      ..add(k)
      ..add(v);
  }
  if (fields.any(bad.hasMatch)) {
    throw ProtocolError('A request line or header contains a line break');
  }
}

List<Header> _withAutoHeaders(
  HttpRequestSpec spec,
  int bodyLength,
  String userAgent,
) {
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
