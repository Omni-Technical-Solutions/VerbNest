import 'dart:convert';

import 'package:sqlite3/sqlite3.dart';
import 'package:verbnest_core/verbnest_core.dart' show Ulid;

import 'errors.dart';
import 'models.dart';
import 'row_mapper.dart';
import 'store_support.dart';
import 'workspace_database.dart';

/// The collection tree: nodes, their order, and copying and moving them.
class TreeStore {
  TreeStore(this._ws, this._clock);

  final WorkspaceDatabase _ws;
  final DateTime Function() _clock;

  static const _step = 1024;

  Database get _db => _ws.db;
  int get _now => _clock().millisecondsSinceEpoch;

  List<NodeInfo> children(String? parentId) {
    // Selects only tree columns (plus the method for request badges) so large
    // request bodies are not read just to draw the sidebar.
    const cols =
        'id, parent_id, kind, type, name, position, '
        "json_extract(data, '\$.method') AS method";
    final rows = parentId == null
        ? _db.select(
            'SELECT $cols FROM node WHERE parent_id IS NULL ORDER BY position, name',
          )
        : _db.select(
            'SELECT $cols FROM node WHERE parent_id = ? ORDER BY position, name',
            [parentId],
          );
    return [for (final r in rows) info(r)];
  }

  NodeInfo node(String id) => info(byId(id));

  /// Every ancestor id from the parent up to the collection.
  List<String> ancestors(String id) {
    final rows = _db.select(
      '''
      WITH RECURSIVE up(id, parent_id) AS (
        SELECT id, parent_id FROM node WHERE id = ?
        UNION ALL
        SELECT n.id, n.parent_id FROM node n JOIN up ON n.id = up.parent_id
      ) SELECT id FROM up
      ''',
      [id],
    );
    return [for (final r in rows.skip(1)) r.str('id')];
  }

  String create(String? parentId, NodeKind kind, String name, {String? type}) {
    return _ws.transaction(() {
      checkParent(parentId, kind);
      final id = Ulid.generate(now: _clock());
      final now = _now;
      _db.execute(
        'INSERT INTO node(id, parent_id, kind, type, name, position, created_at, updated_at) '
        'VALUES (?, ?, ?, ?, ?, ?, ?, ?)',
        [
          id,
          parentId,
          kind.name,
          type,
          name,
          _nextPosition(parentId),
          now,
          now,
        ],
      );
      return id;
    });
  }

  void checkParent(String? parentId, NodeKind kind) {
    if (kind == NodeKind.collection) {
      if (parentId != null) {
        throw const InvalidOperationError('A collection cannot have a parent');
      }
      return;
    }
    if (parentId == null) {
      throw const InvalidOperationError('Folders and requests need a parent');
    }
    if (byId(parentId)['kind'] == 'request') {
      throw const InvalidOperationError('A request cannot contain items');
    }
  }

  int _nextPosition(String? parentId) {
    final rows = parentId == null
        ? _db.select(
            'SELECT MAX(position) AS p FROM node WHERE parent_id IS NULL',
          )
        : _db.select(
            'SELECT MAX(position) AS p FROM node WHERE parent_id = ?',
            [parentId],
          );
    final max = rows.first.integerOrNull('p');
    return max == null ? _step : max + _step;
  }

  void rename(String id, String name) => _ws.transaction(() {
    byId(id);
    _db.execute('UPDATE node SET name = ?, updated_at = ? WHERE id = ?', [
      name,
      _now,
      id,
    ]);
  });

  void delete(String id) => _ws.transaction(() {
    byId(id);
    // Variables point at nodes by id without a foreign key, so remove those
    // of every descendant before the cascade deletes the nodes.
    _db.execute(
      '''
      WITH RECURSIVE sub(id) AS (
        SELECT ? UNION ALL SELECT n.id FROM node n JOIN sub ON n.parent_id = sub.id
      )
      DELETE FROM variable
      WHERE owner_kind IN ('collection','folder') AND owner_id IN (SELECT id FROM sub)
      ''',
      [id],
    );
    _db.execute('DELETE FROM node WHERE id = ?', [id]);
  });

  /// Moves [id] under [newParentId] at [index] among its new siblings.
  void move(String id, String? newParentId, int index) => _ws.transaction(() {
    final row = byId(id);
    final kind = NodeKind.values.byName(row.str('kind'));
    if (kind == NodeKind.collection) {
      if (newParentId != null) {
        throw const InvalidOperationError('A collection cannot be nested');
      }
    } else {
      checkParent(newParentId, kind);
      if (newParentId == id || ancestors(newParentId!).contains(id)) {
        throw const InvalidOperationError('Cannot move an item into itself');
      }
    }
    final siblings = [
      for (final c in children(newParentId))
        if (c.id != id) c.id,
    ];
    siblings.insert(index.clamp(0, siblings.length), id);
    _db.execute('UPDATE node SET parent_id = ? WHERE id = ?', [
      newParentId,
      id,
    ]);
    for (var i = 0; i < siblings.length; i++) {
      _db.execute('UPDATE node SET position = ? WHERE id = ?', [
        (i + 1) * _step,
        siblings[i],
      ]);
    }
    _db.execute('UPDATE node SET updated_at = ? WHERE id = ?', [_now, id]);
  });

  /// Deep-copies [id] next to the original; returns the new root id.
  String duplicate(String id) => _ws.transaction(() {
    final row = byId(id);
    final parentId = row.strOrNull('parent_id');
    final copyId = _copyNode(row, parentId, suffix: ' copy');
    final siblings = children(parentId).map((c) => c.id).toList()
      ..remove(copyId);
    final at = siblings.indexOf(id) + 1;
    move(copyId, parentId, at);
    return copyId;
  });

  String _copyNode(Row row, String? parentId, {String suffix = ''}) {
    final newId = Ulid.generate(now: _clock());
    final now = _now;
    _db.execute(
      'INSERT INTO node(id, parent_id, kind, type, name, position, description, '
      'auth_json, scripts_json, data, extra, created_at, updated_at) '
      'VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)',
      [
        newId,
        parentId,
        row['kind'],
        row['type'],
        '${row['name']}$suffix',
        _nextPosition(parentId),
        row['description'],
        row['auth_json'],
        row['scripts_json'],
        row['data'],
        row['extra'],
        now,
        now,
      ],
    );
    for (final v in _db.select(
      "SELECT * FROM variable WHERE owner_kind IN ('collection','folder') AND owner_id = ?",
      [row['id']],
    )) {
      _db.execute(
        'INSERT INTO variable(id, owner_kind, owner_id, key, value, type, enabled, description, position) '
        'VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)',
        [
          Ulid.generate(now: _clock()),
          v['owner_kind'],
          newId,
          v['key'],
          v['value'],
          v['type'],
          v['enabled'],
          v['description'],
          v['position'],
        ],
      );
    }
    for (final child in _db.select(
      'SELECT * FROM node WHERE parent_id = ? ORDER BY position',
      [row['id']],
    )) {
      _copyNode(child, newId);
    }
    return newId;
  }

  /// Inserts a node with the id it was exported with. The position follows
  /// the order of calls under the same parent.
  void restore(Json n, String? parentId) => _ws.transaction(() {
    final now = _now;
    _db.execute(
      'INSERT INTO node(id, parent_id, kind, type, name, position, description, '
      'auth_json, scripts_json, data, extra, created_at, updated_at) '
      'VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)',
      [
        n['id'],
        parentId,
        n['kind'],
        n['type'],
        n['name'],
        _nextPosition(parentId),
        n['description'] ?? '',
        n['auth'] == null ? null : jsonEncode(n['auth']),
        n['scripts'] == null ? null : jsonEncode(n['scripts']),
        jsonEncode(n['data'] ?? {}),
        jsonEncode(n['extra'] ?? {}),
        now,
        now,
      ],
    );
  });

  Row byId(String id) {
    final rows = _db.select(
      "SELECT *, json_extract(data, '\$.method') AS method FROM node WHERE id = ?",
      [id],
    );
    if (rows.isEmpty) throw NotFoundError('Item $id');
    return rows.first;
  }

  NodeInfo info(Row r) => NodeInfo(
    id: r.str('id'),
    parentId: r.strOrNull('parent_id'),
    kind: NodeKind.values.byName(r.str('kind')),
    type: r.strOrNull('type'),
    name: r.str('name'),
    position: r.integer('position'),
    method: r.strOrNull('method'),
  );
}
