import 'package:sqlite3/sqlite3.dart';

import 'models.dart';
import 'repository_models.dart';
import 'workspace_repository.dart';

class SearchHit {
  const SearchHit({
    required this.id,
    required this.kind,
    required this.name,
    required this.path,
    this.method,
    this.url,
  });

  final String id;
  final NodeKind kind;
  final String name;

  /// Names of the containers above it, collection first.
  final List<String> path;
  final String? method;
  final String? url;
}

/// Full-text search over the workspace tree (FR-COL-003).
///
/// The index lives in memory and is rebuilt from the workspace, so it can
/// never drift from it and nothing derived is written into the shared file.
/// It covers names, descriptions, methods, URLs, header names and raw
/// bodies. Header values are left out because they often hold credentials.
class SearchIndex {
  SearchIndex(this._repo) {
    _open();
  }

  final WorkspaceRepository _repo;
  late Database _db;
  final Map<String, SearchHit> _hits = {};

  void _open() {
    _db = sqlite3.openInMemory();
    _db.execute(
      'CREATE VIRTUAL TABLE idx USING fts5('
      "id UNINDEXED, name, meta, body, tokenize='trigram')",
    );
  }

  int get size => _hits.length;

  void rebuild() {
    _hits.clear();
    _db.execute('DELETE FROM idx');
    final docs = _repo.searchDocuments();
    final byId = {for (final d in docs) d.id: d};
    List<String> pathOf(SearchDoc d) {
      final out = <String>[];
      var p = d.parentId;
      while (p != null && byId[p] != null) {
        out.insert(0, byId[p]!.name);
        p = byId[p]!.parentId;
      }
      return out;
    }

    final stmt = _db.prepare(
      'INSERT INTO idx(id, name, meta, body) VALUES (?,?,?,?)',
    );
    _db.execute('BEGIN');
    for (final d in docs) {
      _hits[d.id] = SearchHit(
        id: d.id,
        kind: d.kind,
        name: d.name,
        path: pathOf(d),
        method: d.method,
        url: d.url,
      );
      stmt.execute([d.id, d.name, d.meta, d.body]);
    }
    _db.execute('COMMIT');
    stmt.close();
  }

  /// Best matches first. Queries under three characters match names only,
  /// because the trigram index needs at least three.
  List<SearchHit> search(String query, {int limit = 50}) {
    final q = query.trim();
    if (q.isEmpty) return const [];
    if (q.length < 3) {
      final lower = q.toLowerCase();
      return [
        for (final h in _hits.values)
          if (h.name.toLowerCase().contains(lower)) h,
      ].take(limit).toList();
    }
    final phrase = '"${q.replaceAll('"', '""')}"';
    final rows = _db.select(
      'SELECT id FROM idx WHERE idx MATCH ? '
      'ORDER BY bm25(idx, 0, 10, 3, 1) LIMIT ?',
      [phrase, limit],
    );
    return [
      for (final r in rows)
        if (_hits[r['id']] != null) _hits[r['id']]!,
    ];
  }

  void dispose() => _db.close();
}
