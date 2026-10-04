import 'package:postit_core/postit_core.dart';

import 'shell_tokenizer.dart';

/// A request parsed from a cURL command plus anything that was ignored.
class CurlImport {
  CurlImport(this.item, this.warnings);

  final HttpRequestItem item;
  final List<String> warnings;
}

bool looksLikeCurl(String text) => RegExp(r'^\s*curl(\s|$)').hasMatch(text);

const _noArg = {
  's', 'S', 'v', 'i', 'f', 'N', '#', 'g', //
  'silent', 'show-error', 'verbose', 'include', 'fail', 'no-buffer',
  'globoff',
  'progress-bar',
  'compressed',
  'http1.1',
  'http2',
  'location-trusted',
  'tr-encoding', 'no-keepalive', 'path-as-is', 'fail-with-body',
};

/// Parses a cURL command (FR-IO-001). Throws [FormatException] when the text
/// is not a cURL command or has no URL.
CurlImport parseCurl(String command, {String name = 'Imported request'}) {
  final words = shellSplit(command.trim());
  if (words.isEmpty || words.first != 'curl') {
    throw const FormatException('Not a cURL command');
  }
  final warnings = <String>[];
  String? method;
  String? url;
  final headers = <KeyValue>[];
  final data = <String>[];
  final form = <KeyValue>[];
  Auth auth = const InheritAuth();
  var verifyTls = true;
  var head = false;
  var getMode = false;
  bool? follow;
  int? timeoutMs;

  String value(List<String> w, int i, String flag) {
    if (i + 1 >= w.length) throw FormatException('$flag needs a value');
    return w[i + 1];
  }

  var i = 1;
  while (i < words.length) {
    final w = words[i];
    String? flag;
    String? inline;
    if (w.startsWith('--') && w.length > 2) {
      final eq = w.indexOf('=');
      flag = eq == -1 ? w.substring(2) : w.substring(2, eq);
      inline = eq == -1 ? null : w.substring(eq + 1);
    } else if (w.startsWith('-') && w.length > 1) {
      flag = w.substring(1);
    } else {
      url ??= w;
      if (url != w) warnings.add('Ignored extra argument "$w"');
      i++;
      continue;
    }

    String arg() => inline ?? value(words, i, w);
    int step() => inline == null ? 2 : 1;

    // Short flags may be bundled (-sSL) or carry their value (-XPOST).
    if (!w.startsWith('--') && flag.length > 1) {
      final first = flag[0];
      if (_takesArg.contains(first)) {
        inline = flag.substring(1);
        flag = first;
      } else {
        for (final ch in flag.split('')) {
          switch (ch) {
            case 'L':
              follow = true;
            case 'k':
              verifyTls = false;
            case 'I':
              head = true;
            case 'G':
              getMode = true;
            default:
              if (!_noArg.contains(ch)) warnings.add('Ignored flag -$ch');
          }
        }
        i++;
        continue;
      }
    }

    switch (flag) {
      case 'X' || 'request':
        method = arg();
        i += step();
      case 'H' || 'header':
        final h = arg();
        final colon = h.indexOf(':');
        if (colon == -1) {
          if (h.endsWith(';')) {
            headers.add(KeyValue(key: h.substring(0, h.length - 1)));
          } else {
            warnings.add('Ignored malformed header "$h"');
          }
        } else {
          headers.add(
            KeyValue(
              key: h.substring(0, colon).trim(),
              value: h.substring(colon + 1).trim(),
            ),
          );
        }
        i += step();
      case 'd' ||
          'data' ||
          'data-raw' ||
          'data-binary' ||
          'data-ascii' ||
          'data-urlencode':
        data.add(arg());
        i += step();
      case 'F' || 'form' || 'form-string':
        final f = arg();
        final eq = f.indexOf('=');
        if (eq == -1) {
          warnings.add('Ignored malformed form field "$f"');
        } else {
          final v = f.substring(eq + 1);
          form.add(
            v.startsWith('@')
                ? KeyValue(
                    key: f.substring(0, eq),
                    value: v.substring(1),
                    type: KeyValueType.file,
                  )
                : KeyValue(key: f.substring(0, eq), value: v),
          );
        }
        i += step();
      case 'u' || 'user':
        final u = arg();
        final colon = u.indexOf(':');
        auth = BasicAuth(
          username: colon == -1 ? u : u.substring(0, colon),
          password: colon == -1 ? '' : u.substring(colon + 1),
        );
        i += step();
      case 'b' || 'cookie':
        headers.add(KeyValue(key: 'Cookie', value: arg()));
        i += step();
      case 'A' || 'user-agent':
        headers.add(KeyValue(key: 'User-Agent', value: arg()));
        i += step();
      case 'e' || 'referer':
        headers.add(KeyValue(key: 'Referer', value: arg()));
        i += step();
      case 'url':
        url = arg();
        i += step();
      case 'm' || 'max-time':
        final secs = double.tryParse(arg());
        if (secs != null) timeoutMs = (secs * 1000).round();
        i += step();
      case 'k' || 'insecure':
        verifyTls = false;
        i++;
      case 'L' || 'location':
        follow = true;
        i++;
      case 'I' || 'head':
        head = true;
        i++;
      case 'G' || 'get':
        getMode = true;
        i++;
      default:
        if (_noArg.contains(flag)) {
          i++;
        } else if (_takesArg.contains(flag) || _longWithArg.contains(flag)) {
          warnings.add(
            'Ignored option ${w.startsWith('--') ? '--' : '-'}$flag',
          );
          i += step();
        } else {
          warnings.add('Ignored unknown option "$w"');
          i++;
        }
    }
  }

  if (url == null) throw const FormatException('No URL in the cURL command');
  var target = url;

  RequestBody body = const NoBody();
  if (getMode && data.isNotEmpty) {
    target += (target.contains('?') ? '&' : '?') + data.join('&');
  } else if (form.isNotEmpty) {
    body = FormDataBody(form);
  } else if (data.isNotEmpty) {
    body = _bodyFor(data.join('&'), headers);
  }

  final resolvedMethod =
      (method ?? (head ? 'HEAD' : (body is NoBody ? 'GET' : 'POST')))
          .toUpperCase();

  // A Basic Authorization header the user already typed becomes Basic auth.
  final authHeader = headers
      .where((h) => h.key.toLowerCase() == 'authorization')
      .firstOrNull;
  if (auth is InheritAuth && authHeader != null) {
    final v = authHeader.value;
    if (v.toLowerCase().startsWith('bearer ')) {
      auth = BearerAuth(token: v.substring(7).trim());
      headers.remove(authHeader);
    }
  }
  if (auth is InheritAuth) auth = const NoAuth();

  final pathNames = UrlText.pathVariables(target);
  return CurlImport(
    HttpRequestItem(
      id: '',
      name: name,
      method: resolvedMethod,
      url: target,
      params: UrlText.params(target),
      pathVars: [for (final n in pathNames) KeyValue(key: n)],
      headers: headers,
      body: body,
      auth: auth,
      settings: RequestSettings(
        verifyTls: verifyTls ? null : false,
        followRedirects: follow ?? false,
        timeoutMs: timeoutMs,
      ),
    ),
    warnings,
  );
}

const _takesArg = {
  'X', 'H', 'd', 'F', 'u', 'b', 'A', 'e', 'm', 'o', 'T', 'x', 'E', 'w', //
};
const _longWithArg = {
  'output',
  'upload-file',
  'proxy',
  'cert',
  'cacert',
  'key',
  'write-out',
  'connect-timeout',
  'max-redirs',
  'retry',
  'resolve',
  'http-version',
  'limit-rate',
  'proxy-user',
  'oauth2-bearer',
  'cookie-jar',
  'dump-header',
};

RequestBody _bodyFor(String text, List<KeyValue> headers) {
  final type =
      headers
          .where((h) => h.key.toLowerCase() == 'content-type')
          .firstOrNull
          ?.value
          .toLowerCase() ??
      '';
  if (type.contains('x-www-form-urlencoded')) {
    return UrlEncodedBody([
      for (final p in text.split('&'))
        if (p.isNotEmpty)
          p.contains('=')
              ? KeyValue(
                  key: p.substring(0, p.indexOf('=')),
                  value: p.substring(p.indexOf('=') + 1),
                )
              : KeyValue(key: p),
    ]);
  }
  if (type.contains('json')) return RawBody(RawBodyLanguage.json, text);
  if (type.contains('xml')) return RawBody(RawBodyLanguage.xml, text);
  if (type.contains('html')) return RawBody(RawBodyLanguage.html, text);
  final t = text.trimLeft();
  if (type.isEmpty && (t.startsWith('{') || t.startsWith('['))) {
    return RawBody(RawBodyLanguage.json, text);
  }
  return RawBody(RawBodyLanguage.text, text);
}

String _q(String s) => "'${s.replaceAll("'", r"'\''")}'";

/// Renders [item] as a cURL command (FR-IO-003). Pass [resolve] to substitute
/// variables; otherwise `{{names}}` stay as they are.
String toCurl(
  HttpRequestItem item, {
  Auth? auth,
  String Function(String)? resolve,
}) {
  String r(String s) => resolve == null ? s : resolve(s);
  final effective = auth ?? item.auth;
  final parts = <String>['curl'];
  final hasBody = item.body is! NoBody;
  final method = item.method.toUpperCase();

  var url = r(item.url);
  if (effective is ApiKeyAuth && effective.addTo == ApiKeyLocation.query) {
    url +=
        '${url.contains('?') ? '&' : '?'}${r(effective.key)}=${r(effective.value)}';
  }
  if (method == 'HEAD') {
    parts.add('-I');
  } else if (method != 'GET' && !(method == 'POST' && hasBody)) {
    parts.addAll(['-X', method]);
  } else if (method == 'POST' && hasBody) {
    parts.addAll(['-X', 'POST']);
  }
  parts.add(_q(url));

  for (final h in item.headers) {
    if (h.enabled && h.key.trim().isNotEmpty) {
      parts.addAll(['-H', _q('${r(h.key)}: ${r(h.value)}')]);
    }
  }
  switch (effective) {
    case BearerAuth(:final token):
      parts.addAll(['-H', _q('Authorization: Bearer ${r(token)}')]);
    case BasicAuth(:final username, :final password):
      parts.addAll(['-u', _q('${r(username)}:${r(password)}')]);
    case ApiKeyAuth(:final key, :final value, :final addTo)
        when addTo == ApiKeyLocation.header:
      parts.addAll(['-H', _q('${r(key)}: ${r(value)}')]);
    default:
  }

  final contentType = item.body.defaultContentType;
  final hasTypeHeader = item.headers.any(
    (h) => h.enabled && h.key.toLowerCase() == 'content-type',
  );
  switch (item.body) {
    case RawBody(:final text):
      if (contentType != null && !hasTypeHeader) {
        parts.addAll(['-H', _q('Content-Type: $contentType')]);
      }
      parts.addAll(['--data-raw', _q(r(text))]);
    case UrlEncodedBody(:final fields):
      final enabled = fields.where((f) => f.enabled);
      parts.addAll([
        '--data-raw',
        _q(enabled.map((f) => '${r(f.key)}=${r(f.value)}').join('&')),
      ]);
    case FormDataBody(:final fields):
      for (final f in fields.where((f) => f.enabled)) {
        final v = f.type == KeyValueType.file ? '@${r(f.value)}' : r(f.value);
        parts.addAll(['-F', _q('${r(f.key)}=$v')]);
      }
    case BinaryBody() || NoBody():
  }

  if (item.settings.verifyTls == false) parts.add('-k');
  if (item.settings.followRedirects ?? true) parts.add('-L');
  return parts.join(' ');
}
