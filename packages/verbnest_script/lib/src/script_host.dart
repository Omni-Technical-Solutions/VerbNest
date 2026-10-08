import 'dart:convert';
import 'dart:io';

import 'package:verbnest_http/verbnest_http.dart';

import 'request_map.dart';

/// What scripts may ask the host to do: `pm.sendRequest` and `pm.cookies`.
abstract interface class ScriptHost {
  /// Sends [request] (`{method, url, headers: [{key, value}], body}`) and
  /// returns the response in the shape of `pm.response`. Throws on failure;
  /// the script's callback then receives the message as its error.
  Future<Map<String, Object?>> send(Map<String, Object?> request);

  /// Cookies that would be sent to [url], by name.
  Map<String, String> cookiesFor(String url);
}

/// Sends script requests through an [HttpEngine], so they share its cookie
/// jar, proxy and certificates. They are not recorded in history and run no
/// scripts of their own.
class EngineScriptHost implements ScriptHost {
  EngineScriptHost(this.engine, {this.settings = const HttpSettings()});

  final HttpEngine engine;
  final HttpSettings settings;

  @override
  Future<Map<String, Object?>> send(Map<String, Object?> request) async {
    final url = Uri.tryParse('${request['url']}');
    if (url == null || !url.hasScheme || url.host.isEmpty) {
      throw FormatException('Invalid URL "${request['url']}"');
    }
    if (url.scheme != 'http' && url.scheme != 'https') {
      throw FormatException('Only http and https URLs can be sent');
    }
    if (_isMetadataOrLinkLocal(url.host)) {
      throw FormatException('Scripts cannot send requests to ${url.host}');
    }
    final body = request['body'] as String?;
    final spec = HttpRequestSpec(
      method: '${request['method'] ?? 'GET'}'.toUpperCase(),
      url: url,
      headers: [
        for (final h in (request['headers'] as List? ?? const []))
          ('${(h as Map)['key']}', '${h['value']}'),
      ],
      body: body == null || body.isEmpty ? null : utf8.encode(body),
      settings: settings,
    );
    return responseToMap(await engine.send(spec));
  }

  @override
  Map<String, String> cookiesFor(String url) {
    final uri = Uri.tryParse(url);
    final header = uri == null ? null : engine.cookieJar?.cookieHeader(uri);
    if (header == null) return const {};
    return {
      for (final pair in header.split(';'))
        if (pair.contains('='))
          pair.substring(0, pair.indexOf('=')).trim(): pair
              .substring(pair.indexOf('=') + 1)
              .trim(),
    };
  }
}

/// Cloud metadata endpoints and link-local addresses hold instance
/// credentials, so scripts never reach them. Hostnames are not resolved here.
bool _isMetadataOrLinkLocal(String host) {
  final h = host.toLowerCase();
  if (h == 'metadata.google.internal' || h == 'metadata') return true;
  final ip = InternetAddress.tryParse(h);
  if (ip == null) return false;
  final raw = ip.rawAddress;
  if (ip.type == InternetAddressType.IPv4) {
    return raw[0] == 169 && raw[1] == 254;
  }
  if (raw[0] == 0xfe && (raw[1] & 0xc0) == 0x80) return true;
  final mapped =
      raw.sublist(0, 10).every((b) => b == 0) &&
      raw[10] == 0xff &&
      raw[11] == 0xff;
  return mapped && raw[12] == 169 && raw[13] == 254;
}
