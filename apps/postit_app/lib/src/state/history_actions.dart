import 'dart:convert';

import 'package:postit_core/postit_core.dart';
import 'package:postit_http/postit_http.dart';
import 'package:postit_storage/postit_storage.dart';

import 'session.dart';

/// True when [entry]'s request still exists in the workspace.
bool requestStillExists(WorkspaceSession s, HistoryEntry entry) {
  final id = entry.requestId;
  if (id == null) return false;
  try {
    s.repo.getRequest(id);
    return true;
  } on NotFoundError {
    return false;
  }
}

/// Builds a request from the stored (masked) history record. Secret values
/// were replaced by [Masker.placeholder] when it was stored, so callers
/// should tell the user to re-enter them.
({HttpRequestItem item, bool hadMasked}) requestFromHistory(
  HistoryEntry entry,
) {
  final j = (jsonDecode(entry.requestJson) as Map).cast<String, Object?>();
  final headers = [
    for (final pair in (j['headers'] as List? ?? const []).cast<List>())
      KeyValue(key: pair[0].toString(), value: pair[1].toString()),
  ];
  final bodyText = j['body'] as String?;
  final url = '${j['url'] ?? entry.url}';
  final type = headers
      .where((h) => h.key.toLowerCase() == 'content-type')
      .firstOrNull
      ?.value
      .toLowerCase();
  final language = switch (type) {
    final t? when t.contains('json') => RawBodyLanguage.json,
    final t? when t.contains('xml') => RawBodyLanguage.xml,
    final t? when t.contains('html') => RawBodyLanguage.html,
    _ => RawBodyLanguage.text,
  };
  final item = HttpRequestItem(
    id: '',
    name: '${entry.method} ${url.replaceFirst(RegExp(r'^\w+://'), '')}',
    method: entry.method,
    url: url,
    params: UrlText.params(url),
    headers: headers,
    body: bodyText == null ? const NoBody() : RawBody(language, bodyText),
  );
  final masked =
      url.contains(Masker.placeholder) ||
      headers.any((h) => h.value.contains(Masker.placeholder)) ||
      (bodyText?.contains(Masker.placeholder) ?? false);
  return (item: item, hadMasked: masked);
}

/// Saves the history entry as a new request in the "Imported" collection.
String saveHistoryAsRequest(WorkspaceSession s, HistoryEntry entry) {
  final parsed = requestFromHistory(entry);
  final target =
      s.repo
          .children(null)
          .where((n) => n.name == 'Imported')
          .firstOrNull
          ?.id ??
      s.repo.createCollection('Imported');
  return s.repo.createRequest(target, parsed.item);
}
