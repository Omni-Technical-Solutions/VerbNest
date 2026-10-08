import 'package:verbnest_core/verbnest_core.dart';

import 'postman.dart';

bool looksLikeHar(Object? json) {
  if (json is! Map) return false;
  final log = json['log'];
  return log is Map && log['entries'] is List;
}

/// Headers that describe the connection the browser used, not the request.
const _skipHeaders = {
  'host',
  'content-length',
  'connection',
  'accept-encoding',
  'upgrade-insecure-requests',
};

/// Imports a HAR capture (FR-IO-004): one request per entry, in order.
PostmanImport importHar(Object? json) {
  if (!looksLikeHar(json)) throw const FormatException('Not a HAR file');
  final log = (json as Map)['log'] as Map;
  final warnings = <String>[];
  final nodes = <ImportNode>[
    for (final raw in log['entries'] as List) ?_entryRequest(raw, warnings),
  ];
  if (nodes.isEmpty) warnings.add('The HAR file has no requests');
  final creator = (log['creator'] is Map)
      ? '${(log['creator'] as Map)['name'] ?? ''}'
      : '';
  return PostmanImport(
    FolderNode(
      creator.isEmpty ? 'HAR import' : 'HAR import ($creator)',
      children: nodes,
    ),
    warnings,
  );
}

/// The request of one HAR entry, or null when the entry has none.
RequestNode? _entryRequest(Object? raw, List<String> warnings) {
  if (raw is! Map || raw['request'] is! Map) return null;
  final r = raw['request'] as Map;
  final url = '${r['url'] ?? ''}';
  if (url.isEmpty) return null;
  final method = '${r['method'] ?? 'GET'}'.toUpperCase();
  final headers = _headers(r['headers']);
  final body = _body(r['postData'], '$method $url', warnings);
  _dropImpliedContentType(headers, body);
  final (base, _, _) = UrlText.split(url);
  final path = base.contains('://')
      ? base.substring(base.indexOf('://') + 3)
      : base;
  return RequestNode(
    HttpRequestItem(
      id: '',
      name: '$method $path',
      method: method,
      url: url,
      params: UrlText.params(url),
      headers: headers,
      body: body,
    ),
  );
}

List<KeyValue> _headers(Object? raw) => [
  for (final h in (raw as List? ?? const []))
    if (h is Map &&
        !'${h['name']}'.startsWith(':') &&
        !_skipHeaders.contains('${h['name']}'.toLowerCase()))
      KeyValue(key: '${h['name']}', value: '${h['value'] ?? ''}'),
];

RequestBody _body(Object? post, String label, List<String> warnings) {
  if (post is! Map) return const NoBody();
  final mime = '${post['mimeType'] ?? ''}'.toLowerCase();
  final text = post['text'];
  final params = post['params'];
  if (mime.contains('x-www-form-urlencoded') && params is List) {
    return UrlEncodedBody([
      for (final p in params)
        if (p is Map)
          KeyValue(key: '${p['name']}', value: '${p['value'] ?? ''}'),
    ]);
  }
  if (mime.contains('multipart/form-data') && params is List) {
    warnings.add('Uploaded files in "$label" need to be picked again');
    return FormDataBody([
      for (final p in params)
        if (p is Map)
          KeyValue(
            key: '${p['name']}',
            value: p['fileName'] != null
                ? '${p['fileName']}'
                : '${p['value'] ?? ''}',
            type: p['fileName'] != null ? KeyValueType.file : KeyValueType.text,
          ),
    ]);
  }
  if (text is String && text.isNotEmpty) {
    return RawBody(_language(mime, text), text);
  }
  return const NoBody();
}

/// The content type is implied by the body mode except for odd types.
void _dropImpliedContentType(List<KeyValue> headers, RequestBody body) {
  final implied = body.defaultContentType;
  final typeHeader = headers
      .where((h) => h.key.toLowerCase() == 'content-type')
      .firstOrNull;
  if (typeHeader != null &&
      implied != null &&
      typeHeader.value.split(';').first.trim().toLowerCase() == implied) {
    headers.remove(typeHeader);
  }
}

RawBodyLanguage _language(String mime, String text) {
  if (mime.contains('json')) return RawBodyLanguage.json;
  if (mime.contains('xml')) return RawBodyLanguage.xml;
  if (mime.contains('html')) return RawBodyLanguage.html;
  if (mime.contains('javascript')) return RawBodyLanguage.javascript;
  return RawBodyLanguage.text;
}
