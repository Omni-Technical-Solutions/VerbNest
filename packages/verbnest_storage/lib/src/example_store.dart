import 'dart:convert';
import 'dart:typed_data';

import 'package:sqlite3/sqlite3.dart';
import 'package:verbnest_core/verbnest_core.dart' show Ulid;

import 'errors.dart';
import 'repository_models.dart';
import 'row_mapper.dart';
import 'store_support.dart';
import 'workspace_database.dart';

/// Saved responses of a request (FR-COL-005).
class ExampleStore {
  ExampleStore(this._ws, this._clock, this._requireNode);

  final WorkspaceDatabase _ws;
  final DateTime Function() _clock;

  /// Throws when [id] is not a node of the workspace.
  final void Function(String id) _requireNode;

  Database get _db => _ws.db;

  List<ExampleInfo> forRequest(String requestId) => [
    for (final r in _db.select(
      'SELECT * FROM example WHERE request_id = ? ORDER BY position, id',
      [requestId],
    ))
      _info(r),
  ];

  ExampleInfo get(String id) {
    final rows = _db.select('SELECT * FROM example WHERE id = ?', [id]);
    if (rows.isEmpty) throw NotFoundError('Example $id');
    return _info(rows.first);
  }

  ExampleInfo _info(Row r) => ExampleInfo(
    id: r.str('id'),
    requestId: r.str('request_id'),
    name: r.str('name'),
    data: decodeJson(r['data']),
    body: (r['body_blob'] as Uint8List?) ?? Uint8List(0),
  );

  /// Adds a saved response for [requestId] and returns its id. [data] holds
  /// `status`, `reason`, `headers` and optionally `request`.
  String add(String requestId, String name, Json data, Uint8List body) =>
      _ws.transaction(() {
        _requireNode(requestId);
        return restore(
          ExampleInfo(
            id: Ulid.generate(now: _clock()),
            requestId: requestId,
            name: name,
            data: data,
            body: body,
          ),
        );
      });

  /// Inserts or replaces an example keeping its id.
  String restore(ExampleInfo e) => _ws.transaction(() {
    final old = _db.select('SELECT position FROM example WHERE id = ?', [e.id]);
    final pos = old.isNotEmpty
        ? old.first.integer('position')
        : ((_db.select(
                        'SELECT MAX(position) AS p FROM example WHERE request_id = ?',
                        [e.requestId],
                      ).first['p']
                      as int?) ??
                  0) +
              positionStep;
    _db.execute(
      'INSERT INTO example(id, request_id, name, position, data, body_blob) '
      'VALUES (?, ?, ?, ?, ?, ?) ON CONFLICT(id) DO UPDATE SET '
      'name = excluded.name, data = excluded.data, body_blob = excluded.body_blob',
      [e.id, e.requestId, e.name, pos, jsonEncode(e.data), e.body],
    );
    return e.id;
  });

  void rename(String id, String name) => _ws.transaction(
    () => _db.execute('UPDATE example SET name = ? WHERE id = ?', [name, id]),
  );

  void delete(String id) => _ws.transaction(
    () => _db.execute('DELETE FROM example WHERE id = ?', [id]),
  );
}
