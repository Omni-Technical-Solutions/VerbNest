import 'package:sqlite3/sqlite3.dart';
import 'package:verbnest_core/verbnest_core.dart';

import 'errors.dart';
import 'models.dart';
import 'row_mapper.dart';
import 'store_support.dart';

/// The saved versions of a request (FR-WS-008).
class RevisionStore {
  RevisionStore(this._db, this._now, this.maxRevisions);

  final Database _db;
  final int Function() _now;
  final int maxRevisions;

  /// Adds [snapshot] as the next revision of [id], unless it equals the last
  /// one, and drops the oldest beyond [maxRevisions].
  void add(String id, String snapshot) {
    final last = _db.select(
      'SELECT rev, snapshot FROM revision WHERE node_id = ? ORDER BY rev DESC LIMIT 1',
      [id],
    );
    if (last.isNotEmpty && last.first['snapshot'] == snapshot) return;
    final rev = last.isEmpty ? 1 : (last.first.integer('rev')) + 1;
    _db.execute(
      'INSERT INTO revision(node_id, rev, saved_at, snapshot) VALUES (?, ?, ?, ?)',
      [id, rev, _now(), snapshot],
    );
    _db.execute('DELETE FROM revision WHERE node_id = ? AND rev <= ?', [
      id,
      rev - maxRevisions,
    ]);
  }

  List<RevisionInfo> list(String id) => [
    for (final r in _db.select(
      'SELECT rev, saved_at FROM revision WHERE node_id = ? ORDER BY rev DESC',
      [id],
    ))
      RevisionInfo(
        rev: r.integer('rev'),
        savedAt: DateTime.fromMillisecondsSinceEpoch(r.integer('saved_at')),
      ),
  ];

  /// The request as it was at [rev].
  HttpRequestItem at(String id, int rev) {
    final rows = _db.select(
      'SELECT snapshot FROM revision WHERE node_id = ? AND rev = ?',
      [id, rev],
    );
    if (rows.isEmpty) throw NotFoundError('Revision $rev of $id');
    final s = decodeJson(rows.first['snapshot']);
    return HttpRequestItem.fromData(
      id: id,
      name: s['name'] as String,
      data: (s['data'] as Map).cast<String, Object?>(),
      auth: (s['auth'] as Map?)?.cast<String, Object?>(),
      scripts: (s['scripts'] as Map?)?.cast<String, Object?>(),
      description: s['description'] as String? ?? '',
    );
  }
}
