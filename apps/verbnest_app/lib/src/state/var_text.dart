import 'package:verbnest_core/verbnest_core.dart';

/// A `{{name}}` reference inside a text.
class VarToken {
  const VarToken(this.start, this.end, this.name);

  final int start;
  final int end;
  final String name;
}

final _token = RegExp(r'\{\{\s*([^{}\s]+)\s*\}\}');

List<VarToken> findTokens(String text) => [
  for (final m in _token.allMatches(text)) VarToken(m.start, m.end, m[1]!),
];

/// The token the caret is in or touches, if any.
VarToken? tokenAt(String text, int caret) {
  for (final t in findTokens(text)) {
    if (caret >= t.start && caret <= t.end) return t;
  }
  return null;
}

/// The name typed so far after an unclosed `{{` before [caret], or null.
String? completionPrefix(String text, int caret) {
  if (caret < 0 || caret > text.length) return null;
  final before = text.substring(0, caret);
  final open = before.lastIndexOf('{{');
  if (open < 0) return null;
  final typed = before.substring(open + 2);
  if (typed.contains('}') || typed.contains('{') || typed.contains(' ')) {
    return null;
  }
  return typed;
}

/// Replaces the partial name before [caret] with `{{name}}`.
({String text, int caret}) applyCompletion(
  String text,
  int caret,
  String name,
) {
  final open = text.substring(0, caret).lastIndexOf('{{');
  var end = caret;
  // Swallow an auto-closed or already present `}}` right after the caret.
  if (text.startsWith('}}', end)) end += 2;
  final insert = '{{$name}}';
  return (
    text: text.replaceRange(open, end, insert),
    caret: open + insert.length,
  );
}

/// `key: value` per line; a leading `//` marks a disabled row.
String formatBulk(List<KeyValue> rows) =>
    [for (final r in rows) '${r.enabled ? '' : '// '}${r.key}: ${r.value}']
        .join('\n');

List<KeyValue> parseBulk(String text) {
  final out = <KeyValue>[];
  for (var line in text.split('\n')) {
    line = line.trimRight();
    if (line.trim().isEmpty) continue;
    var enabled = true;
    if (line.trimLeft().startsWith('//')) {
      enabled = false;
      line = line.trimLeft().substring(2).trimLeft();
    }
    final i = line.indexOf(':');
    final key = (i < 0 ? line : line.substring(0, i)).trim();
    final value = i < 0 ? '' : line.substring(i + 1).trim();
    out.add(KeyValue(key: key, value: value, enabled: enabled));
  }
  return out;
}

const headerNames = [
  'Accept',
  'Accept-Charset',
  'Accept-Encoding',
  'Accept-Language',
  'Authorization',
  'Cache-Control',
  'Content-Type',
  'Cookie',
  'If-Modified-Since',
  'If-None-Match',
  'Origin',
  'Referer',
  'User-Agent',
  'X-Api-Key',
  'X-Requested-With',
];

const contentTypes = [
  'application/json',
  'application/xml',
  'application/x-www-form-urlencoded',
  'multipart/form-data',
  'text/plain',
  'text/html',
  'application/octet-stream',
];

/// Suggestions from [options] for [typed]: prefix matches first, then
/// substring matches, never the exact text itself.
List<String> matchSuggestions(
  Iterable<String> options,
  String typed, {
  int max = 6,
}) {
  final t = typed.toLowerCase();
  if (t.isEmpty) return const [];
  final prefix = <String>[];
  final inner = <String>[];
  for (final o in options) {
    final l = o.toLowerCase();
    if (l == t) continue;
    if (l.startsWith(t)) {
      prefix.add(o);
    } else if (l.contains(t)) {
      inner.add(o);
    }
  }
  return [...prefix, ...inner].take(max).toList();
}

/// Headers the engine adds on its own, unless the request sets the same name.
List<(String name, String value)> autoHeaders(
  HttpRequestItem item,
  Auth effectiveAuth, {
  String userAgent = 'Verbnest',
  bool autoDecompress = true,
}) {
  final set = {
    for (final h in item.headers)
      if (h.enabled) h.key.toLowerCase(),
  };
  final out = <(String, String)>[];
  void add(String n, String v) {
    if (!set.contains(n.toLowerCase())) out.add((n, v));
  }

  final host = UrlText.split(item.url).$1.replaceFirst(RegExp(r'^\w+://'), '');
  add(
    'Host',
    host.split('/').first.isEmpty ? '<from URL>' : host.split('/').first,
  );
  add('User-Agent', userAgent);
  add('Accept', '*/*');
  if (autoDecompress) add('Accept-Encoding', 'gzip, deflate');
  add('Connection', 'close');
  final ct = item.body.defaultContentType;
  if (ct != null) add('Content-Type', ct);
  if (item.body is FormDataBody) {
    add('Content-Type', 'multipart/form-data; boundary=<generated>');
  }
  if (item.body is! NoBody) add('Content-Length', '<calculated>');
  switch (effectiveAuth) {
    case BearerAuth():
      add('Authorization', 'Bearer <token>');
    case BasicAuth():
      add('Authorization', 'Basic <encoded>');
    case OAuth2Auth():
      add('Authorization', 'Bearer <token>');
    default:
  }
  return out;
}
