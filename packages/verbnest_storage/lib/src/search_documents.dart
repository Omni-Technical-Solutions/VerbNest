import 'dart:convert';

import 'package:sqlite3/sqlite3.dart';
import 'package:verbnest_core/verbnest_core.dart';

import 'models.dart';
import 'repository_models.dart';

/// Text of every node in [db] for [SearchIndex]. Header values are not
/// included.
List<SearchDoc> readSearchDocuments(Database db) => [
  for (final r in db.select(
    'SELECT id, parent_id, kind, name, description, data FROM node',
  ))
    _documentOf(r),
];

SearchDoc _documentOf(Row r) {
  final kind = NodeKind.values.byName(r['kind'] as String);
  if (kind != NodeKind.request) {
    return SearchDoc(
      id: r['id'] as String,
      parentId: r['parent_id'] as String?,
      kind: kind,
      name: r['name'] as String,
      meta: r['description'] as String,
    );
  }
  final item = HttpRequestItem.fromData(
    id: r['id'] as String,
    name: r['name'] as String,
    data: (jsonDecode(r['data'] as String) as Map).cast<String, Object?>(),
    description: r['description'] as String,
  );
  return SearchDoc(
    id: item.id,
    parentId: r['parent_id'] as String?,
    kind: kind,
    name: item.name,
    method: item.method,
    url: item.url,
    meta:
        '${item.method} ${item.url} ${item.description} '
        '${item.headers.map((h) => h.key).join(' ')}',
    body: switch (item.body) {
      RawBody(:final text) => text,
      GraphqlBody(:final query) => query,
      _ => '',
    },
  );
}
