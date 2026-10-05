import 'package:postit_core/postit_core.dart';
import 'package:postit_http/postit_http.dart';

/// The request as a script sees it before variables are replaced: the
/// enabled headers and the raw body text.
Map<String, Object?> requestToMap(HttpRequestItem item) => {
  'method': item.method,
  'url': item.url,
  'headers': [
    for (final h in item.headers)
      if (h.enabled && h.key.isNotEmpty) {'key': h.key, 'value': h.value},
  ],
  'body': switch (item.body) {
    RawBody(:final text) => text,
    GraphqlBody() && final g => g.toPayload(lenient: true),
    _ => '',
  },
};

/// Puts what a pre-request script changed back into [item]. Disabled
/// headers stay; a body change only applies to raw bodies, or turns an empty
/// body into a text body.
HttpRequestItem applyRequestMap(
  HttpRequestItem item,
  Map<String, Object?> map,
) {
  final url = map['url'] as String? ?? item.url;
  final method = (map['method'] as String? ?? item.method).trim();
  final scripted = [
    for (final h in (map['headers'] as List? ?? const []))
      KeyValue(
        key: (h as Map)['key'] as String,
        value: h['value'] as String? ?? '',
      ),
  ];
  var result = item.copyWith(
    method: method.isEmpty ? item.method : method.toUpperCase(),
    headers: [...scripted, ...item.headers.where((h) => !h.enabled)],
  );
  if (url != item.url) {
    final oldVars = {for (final v in item.pathVars) v.key: v};
    result = result.copyWith(
      url: url,
      params: [...UrlText.params(url), ...item.params.where((p) => !p.enabled)],
      pathVars: [
        for (final n in UrlText.pathVariables(url))
          oldVars[n] ?? KeyValue(key: n),
      ],
    );
  }
  final body = map['body'] as String? ?? '';
  final current = item.body;
  if (current is RawBody && current.text != body) {
    result = result.copyWith(body: RawBody(current.language, body));
  } else if (current is GraphqlBody) {
    // A script that rewrites the payload turns it into a plain JSON body for
    // this send only; an untouched payload keeps the GraphQL editor fields.
    if (current.toPayload(lenient: true) != body) {
      result = result.copyWith(body: RawBody(RawBodyLanguage.json, body));
    }
  } else if (current is! RawBody && body.isNotEmpty) {
    result = result.copyWith(body: RawBody(RawBodyLanguage.text, body));
  }
  return result;
}

/// The response as scripts see it.
Map<String, Object?> responseToMap(HttpResponseRecord r) => {
  'code': r.status,
  'status': r.reason,
  'headers': [
    for (final (k, v) in r.headers) {'key': k, 'value': v},
  ],
  'body': r.bodyText,
  'time': r.timings.total.inMilliseconds,
  'size': r.body.length,
};
