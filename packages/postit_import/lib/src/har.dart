import 'package:postit_core/postit_core.dart';

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
  final nodes = <ImportNode>[];
  for (final raw in log['entries'] as List) {
    if (raw is! Map || raw['request'] is! Map) continue;
    final r = raw['request'] as Map;
    final url = '${r['url'] ?? ''}';
    if (url.isEmpty) continue;
    final method = '${r['method'] ?? 'GET'}'.toUpperCase();
    final headers = <KeyValue>[
      for (final h in (r['headers'] as List? ?? const []))
        if (h is Map &&
            !'${h['name']}'.startsWith(':') &&
            !_skipHeaders.contains('${h['name']}'.toLowerCase()))
          KeyValue(key: '${h['name']}', value: '${h['value'] ?? ''}'),
    ];
    final post = r['postData'];
    var body = const NoBody() as RequestBody;
    if (post is Map) {
      final mime = '${post['mimeType'] ?? ''}'.toLowerCase();
      final text = post['text'];
      final params = post['params'];
      if (mime.contains('x-www-form-urlencoded') && params is List) {
        body = UrlEncodedBody([
          for (final p in params)
            if (p is Map)
              KeyValue(key: '${p['name']}', value: '${p['value'] ?? ''}'),
        ]);
      } else if (mime.contains('multipart/form-data') && params is List) {
        body = FormDataBody([
          for (final p in params)
            if (p is Map)
              KeyValue(
                key: '${p['name']}',
                value: p['fileName'] != null
                    ? '${p['fileName']}'
                    : '${p['value'] ?? ''}',
                type: p['fileName'] != null
                    ? KeyValueType.file
                    : KeyValueType.text,
              ),
        ]);
        warnings.add(
          'Uploaded files in "$method $url" need to be picked again',
        );
      } else if (text is String && text.isNotEmpty) {
        body = RawBody(_language(mime, text), text);
      }
    }
    // The content type is implied by the body mode except for odd types.
    final implied = body.defaultContentType;
    final typeHeader = headers
        .where((h) => h.key.toLowerCase() == 'content-type')
        .firstOrNull;
    if (typeHeader != null &&
        implied != null &&
        typeHeader.value.split(';').first.trim().toLowerCase() == implied) {
      headers.remove(typeHeader);
    }
    final (base, _, _) = UrlText.split(url);
    final path = base.contains('://')
        ? base.substring(base.indexOf('://') + 3)
        : base;
    nodes.add(
      RequestNode(
        HttpRequestItem(
          id: '',
          name: '$method $path',
          method: method,
          url: url,
          params: UrlText.params(url),
          headers: headers,
          body: body,
        ),
      ),
    );
  }
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

RawBodyLanguage _language(String mime, String text) {
  if (mime.contains('json')) return RawBodyLanguage.json;
  if (mime.contains('xml')) return RawBodyLanguage.xml;
  if (mime.contains('html')) return RawBodyLanguage.html;
  if (mime.contains('javascript')) return RawBodyLanguage.javascript;
  return RawBodyLanguage.text;
}
