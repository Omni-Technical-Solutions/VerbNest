import 'dart:typed_data';

import 'package:sqlite3/sqlite3.dart';
import 'package:verbnest_core/verbnest_core.dart' show Ulid;

import 'errors.dart';
import 'repository_models.dart';

/// Files kept inside the workspace file.
class AttachmentStore {
  AttachmentStore(this._db, this._clock);

  final Database _db;
  final DateTime Function() _clock;

  String add(String name, Uint8List bytes, {String? mime}) {
    final id = Ulid.generate(now: _clock());
    _db.execute(
      'INSERT INTO attachment(id, name, mime, content, created_at) '
      'VALUES (?, ?, ?, ?, ?)',
      [id, name, mime, bytes, _clock().millisecondsSinceEpoch],
    );
    return id;
  }

  AttachmentInfo? info(String id) {
    final rows = _db.select(
      'SELECT id, name, mime, length(content) AS size FROM attachment '
      'WHERE id = ?',
      [id],
    );
    if (rows.isEmpty) return null;
    final r = rows.first;
    return AttachmentInfo(
      id: r['id'] as String,
      name: r['name'] as String,
      mime: r['mime'] as String?,
      size: r['size'] as int,
    );
  }

  Uint8List bytes(String id) {
    final rows = _db.select('SELECT content FROM attachment WHERE id = ?', [
      id,
    ]);
    if (rows.isEmpty) throw NotFoundError('Attachment $id');
    return rows.first['content'] as Uint8List;
  }

  void delete(String id) =>
      _db.execute('DELETE FROM attachment WHERE id = ?', [id]);

  /// Deletes attachments that no request, example or revision mentions.
  /// Ids are unique strings, so a text search of the stored JSON is enough.
  int pruneUnreferenced() {
    final unseen = {
      for (final r in _db.select('SELECT id FROM attachment'))
        r['id'] as String,
    };
    if (unseen.isEmpty) return 0;
    final all = {...unseen};
    // One pass over the stored JSON; an id found once need not be searched
    // for again, and the pass ends early when every id has been seen.
    for (final sql in const [
      'SELECT data FROM node',
      'SELECT data FROM example',
      'SELECT snapshot FROM revision',
    ]) {
      for (final r in _db.select(sql)) {
        final text = r.values.first as String?;
        if (text == null) continue;
        unseen.removeWhere(text.contains);
        if (unseen.isEmpty) return prune(all);
      }
    }
    return prune(all.difference(unseen));
  }

  /// Deletes every attachment not named in [referenced]. Returns the count.
  int prune(Set<String> referenced) {
    final all = [
      for (final r in _db.select('SELECT id FROM attachment'))
        r['id'] as String,
    ];
    final orphans = all.where((id) => !referenced.contains(id)).toList();
    for (final id in orphans) {
      delete(id);
    }
    return orphans.length;
  }
}
