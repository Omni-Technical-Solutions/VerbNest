import 'dart:convert';

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
