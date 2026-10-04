import 'dart:convert';

import 'package:postit_core/postit_core.dart';
import 'package:sqlite3/sqlite3.dart';

import 'errors.dart';
import 'models.dart';
import 'workspace_database.dart';

typedef Json = Map<String, Object?>;

/// Reads and writes workspace content: the collection tree, requests,
/// environments, variables and revisions.
class WorkspaceRepository {
  WorkspaceRepository(
    this._ws, {
    DateTime Function()? clock,
    this.maxRevisions = 50,
  }) : _clock = clock ?? DateTime.now;

  final WorkspaceDatabase _ws;
  final DateTime Function() _clock;
  final int maxRevisions;

  static const _step = 1024;

  Database get _db => _ws.db;
  int get _now => _clock().millisecondsSinceEpoch;

  /// Fires after every committed write; use it to refresh the tree.
  Stream<void> get changes => _ws.changes;

  // ---- workspace meta -------------------------------------------------

  String? meta(String key) {
    final rows = _db.select('SELECT value FROM meta WHERE key = ?', [key]);
    return rows.isEmpty ? null : rows.first['value'] as String;
  }

  void setMeta(String key, String value) => _ws.transaction(() {
    _db.execute(
      'INSERT INTO meta(key, value) VALUES (?, ?) '
      'ON CONFLICT(key) DO UPDATE SET value = excluded.value',
      [key, value],
    );
  });

  /// Workspace id, created on first use.
  String get workspaceId {
    final existing = meta('workspace_id');
    if (existing != null) return existing;
    final id = Ulid.generate();
    setMeta('workspace_id', id);
    return id;
  }

  String get name => meta('name') ?? 'Workspace';
  set name(String value) => setMeta('name', value);

  Json get settings => (jsonDecode(meta('settings_json') ?? '{}') as Map)
      .cast<String, Object?>();
  set settings(Json value) => setMeta('settings_json', jsonEncode(value));

  // ---- tree -----------------------------------------------------------

  List<NodeInfo> children(String? parentId) {
    final rows = parentId == null
        ? _db.select(
            'SELECT * FROM node WHERE parent_id IS NULL ORDER BY position, name',
          )
        : _db.select(
            'SELECT * FROM node WHERE parent_id = ? ORDER BY position, name',
            [parentId],
          );
    return [for (final r in rows) _info(r)];
  }

  NodeInfo node(String id) => _info(_row(id));

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
    return [for (final r in rows.skip(1)) r['id'] as String];
  }

  String createCollection(String name) =>
      _create(null, NodeKind.collection, name);

  String createFolder(String parentId, String name) =>
      _create(parentId, NodeKind.folder, name);

  /// Creates a request under [parentId]; the id of [draft] is ignored and a
  /// fresh one is generated.
  String createRequest(String parentId, HttpRequestItem draft) {
    final id = _create(parentId, NodeKind.request, draft.name, type: 'http');
    saveRequest(
      HttpRequestItem.fromData(
        id: id,
        name: draft.name,
        data: draft.toData(),
        auth: draft.auth.toJson(),
        scripts: draft.scripts.toJson(),
        description: draft.description,
      ),
    );
    return id;
  }

  String _create(String? parentId, NodeKind kind, String name, {String? type}) {
    return _ws.transaction(() {
      _checkParent(parentId, kind);
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

  void _checkParent(String? parentId, NodeKind kind) {
    if (kind == NodeKind.collection) {
      if (parentId != null) {
        throw const InvalidOperationError('A collection cannot have a parent');
      }
      return;
    }
    if (parentId == null) {
      throw const InvalidOperationError('Folders and requests need a parent');
    }
    if (_row(parentId)['kind'] == 'request') {
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
    final max = rows.first['p'] as int?;
    return max == null ? _step : max + _step;
  }

  void rename(String id, String name) => _ws.transaction(() {
    _row(id);
    _db.execute('UPDATE node SET name = ?, updated_at = ? WHERE id = ?', [
      name,
      _now,
      id,
    ]);
  });

  void delete(String id) => _ws.transaction(() {
    _row(id);
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
    final row = _row(id);
    final kind = NodeKind.values.byName(row['kind'] as String);
    if (kind == NodeKind.collection) {
      if (newParentId != null) {
        throw const InvalidOperationError('A collection cannot be nested');
      }
    } else {
      _checkParent(newParentId, kind);
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
    final row = _row(id);
    final parentId = row['parent_id'] as String?;
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

  // ---- containers (collections and folders) -----------------------------

  Auth containerAuth(String id) =>
      Auth.fromJson(_decodeOrNull(_row(id)['auth_json']));

  void setContainerAuth(String id, Auth auth) => _ws.transaction(() {
    _row(id);
    _db.execute('UPDATE node SET auth_json = ?, updated_at = ? WHERE id = ?', [
      jsonEncode(auth.toJson()),
      _now,
      id,
    ]);
  });

  String description(String id) => _row(id)['description'] as String;

  void setDescription(String id, String text) => _ws.transaction(() {
    _row(id);
    _db.execute(
      'UPDATE node SET description = ?, updated_at = ? WHERE id = ?',
      [text, _now, id],
    );
  });

  /// Auth of each ancestor of [id], nearest first, for [effectiveAuth].
  List<Auth> authChain(String id) => [
    for (final a in ancestors(id)) containerAuth(a),
  ];

  // ---- requests -------------------------------------------------------

  HttpRequestItem getRequest(String id) {
    final r = _row(id);
    if (r['kind'] != 'request') {
      throw InvalidOperationError('$id is not a request');
    }
    return HttpRequestItem.fromData(
      id: id,
      name: r['name'] as String,
      data: _decode(r['data']),
      auth: _decodeOrNull(r['auth_json']),
      scripts: _decodeOrNull(r['scripts_json']),
      description: r['description'] as String,
    );
  }

  /// Saves [item] and records a revision when anything changed.
  void saveRequest(HttpRequestItem item) => _ws.transaction(() {
    final before = _row(item.id);
    if (before['kind'] != 'request') {
      throw InvalidOperationError('${item.id} is not a request');
    }
    final snapshot = _snapshot(item);
    _db.execute(
      'UPDATE node SET name = ?, description = ?, auth_json = ?, scripts_json = ?, '
      'data = ?, updated_at = ? WHERE id = ?',
      [
        item.name,
        item.description,
        jsonEncode(item.auth.toJson()),
        jsonEncode(item.scripts.toJson()),
        jsonEncode(item.toData()),
        _now,
        item.id,
      ],
    );
    _addRevision(item.id, snapshot);
  });

  String _snapshot(HttpRequestItem i) => jsonEncode({
    'name': i.name,
    'description': i.description,
    'auth': i.auth.toJson(),
    'scripts': i.scripts.toJson(),
    'data': i.toData(),
  });

  // ---- revisions (FR-WS-008) -------------------------------------------

  void _addRevision(String id, String snapshot) {
    final last = _db.select(
      'SELECT rev, snapshot FROM revision WHERE node_id = ? ORDER BY rev DESC LIMIT 1',
      [id],
    );
    if (last.isNotEmpty && last.first['snapshot'] == snapshot) return;
    final rev = last.isEmpty ? 1 : (last.first['rev'] as int) + 1;
    _db.execute(
      'INSERT INTO revision(node_id, rev, saved_at, snapshot) VALUES (?, ?, ?, ?)',
      [id, rev, _now, snapshot],
    );
    _db.execute('DELETE FROM revision WHERE node_id = ? AND rev <= ?', [
      id,
      rev - maxRevisions,
    ]);
  }

  List<RevisionInfo> revisions(String id) => [
    for (final r in _db.select(
      'SELECT rev, saved_at FROM revision WHERE node_id = ? ORDER BY rev DESC',
      [id],
    ))
      RevisionInfo(
        rev: r['rev'] as int,
        savedAt: DateTime.fromMillisecondsSinceEpoch(r['saved_at'] as int),
      ),
  ];

  /// The request as it was at [rev].
  HttpRequestItem revision(String id, int rev) {
    final rows = _db.select(
      'SELECT snapshot FROM revision WHERE node_id = ? AND rev = ?',
      [id, rev],
    );
    if (rows.isEmpty) throw NotFoundError('Revision $rev of $id');
    final s = _decode(rows.first['snapshot']);
    return HttpRequestItem.fromData(
      id: id,
      name: s['name'] as String,
      data: (s['data'] as Map).cast<String, Object?>(),
      auth: (s['auth'] as Map?)?.cast<String, Object?>(),
      scripts: (s['scripts'] as Map?)?.cast<String, Object?>(),
      description: s['description'] as String? ?? '',
    );
  }

  /// Makes [rev] the current version; recorded as a new revision.
  void restoreRevision(String id, int rev) => saveRequest(revision(id, rev));

  // ---- variables --------------------------------------------------------

  List<Variable> variables(VariableOwner owner) => [
    for (final r in _db.select(
      'SELECT * FROM variable WHERE owner_kind = ? AND owner_id = ? ORDER BY position',
      [owner.kind, owner.id],
    ))
      Variable(
        key: r['key'] as String,
        value: (r['value'] as String?) ?? '',
        secret: r['type'] == 'secret',
        enabled: (r['enabled'] as int) != 0,
        description: r['description'] as String,
      ),
  ];

  /// Replaces all variables of [owner]. Secret values are never stored
  /// (constitution II.4); they belong in the secret store.
  void saveVariables(VariableOwner owner, List<Variable> vars) =>
      _ws.transaction(() => _replaceVariables(owner, vars));

  void _replaceVariables(VariableOwner owner, List<Variable> vars) {
    _db.execute('DELETE FROM variable WHERE owner_kind = ? AND owner_id = ?', [
      owner.kind,
      owner.id,
    ]);
    final seen = <String>{};
    for (var i = 0; i < vars.length; i++) {
      final v = vars[i];
      if (!seen.add(v.key)) throw DuplicateNameError(v.key);
      _db.execute(
        'INSERT INTO variable(id, owner_kind, owner_id, key, value, type, enabled, description, position) '
        'VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)',
        [
          Ulid.generate(now: _clock()),
          owner.kind,
          owner.id,
          v.key,
          v.secret ? null : v.value,
          v.secret ? 'secret' : 'default',
          v.enabled ? 1 : 0,
          v.description,
          (i + 1) * _step,
        ],
      );
    }
  }

  // ---- environments -----------------------------------------------------

  List<Environment> environments() => [
    for (final r in _db.select(
      'SELECT * FROM environment ORDER BY position, name',
    ))
      Environment(
        id: r['id'] as String,
        name: r['name'] as String,
        color: r['color'] as String?,
        variables: variables(VariableOwner.environment(r['id'] as String)),
      ),
  ];

  Environment environment(String id) {
    final rows = _db.select('SELECT * FROM environment WHERE id = ?', [id]);
    if (rows.isEmpty) throw NotFoundError('Environment $id');
    return environments().firstWhere((e) => e.id == id);
  }

  /// Inserts or updates [env] together with its variables.
  void saveEnvironment(Environment env) => _ws.transaction(() {
    final exists = _db.select('SELECT 1 FROM environment WHERE id = ?', [
      env.id,
    ]);
    try {
      if (exists.isEmpty) {
        _db.execute(
          'INSERT INTO environment(id, name, color, position) VALUES (?, ?, ?, ?)',
          [env.id, env.name, env.color, _nextEnvPosition()],
        );
      } else {
        _db.execute('UPDATE environment SET name = ?, color = ? WHERE id = ?', [
          env.name,
          env.color,
          env.id,
        ]);
      }
    } on SqliteException catch (e) {
      if (e.extendedResultCode == 2067) throw DuplicateNameError(env.name);
      rethrow;
    }
    _replaceVariables(VariableOwner.environment(env.id), env.variables);
  });

  int _nextEnvPosition() {
    final max =
        _db.select('SELECT MAX(position) AS p FROM environment').first['p']
            as int?;
    return max == null ? _step : max + _step;
  }

  void deleteEnvironment(String id) => _ws.transaction(() {
    _db.execute('DELETE FROM environment WHERE id = ?', [id]);
    _db.execute(
      "DELETE FROM variable WHERE owner_kind = 'environment' AND owner_id = ?",
      [id],
    );
    if (meta('default_environment_id') == id) {
      _db.execute("DELETE FROM meta WHERE key = 'default_environment_id'");
    }
  });

  String? get defaultEnvironmentId => meta('default_environment_id');
  set defaultEnvironmentId(String? id) {
    if (id == null) {
      _ws.transaction(
        () => _db.execute(
          "DELETE FROM meta WHERE key = 'default_environment_id'",
        ),
      );
    } else {
      setMeta('default_environment_id', id);
    }
  }

  // ---- helpers ----------------------------------------------------------

  Row _row(String id) {
    final rows = _db.select('SELECT * FROM node WHERE id = ?', [id]);
    if (rows.isEmpty) throw NotFoundError('Item $id');
    return rows.first;
  }

  NodeInfo _info(Row r) => NodeInfo(
    id: r['id'] as String,
    parentId: r['parent_id'] as String?,
    kind: NodeKind.values.byName(r['kind'] as String),
    type: r['type'] as String?,
    name: r['name'] as String,
    position: r['position'] as int,
  );

  Json _decode(Object? text) =>
      (jsonDecode(text as String) as Map).cast<String, Object?>();

  Json? _decodeOrNull(Object? text) => text == null ? null : _decode(text);
}

/// Who owns a set of variables.
class VariableOwner {
  const VariableOwner._(this.kind, this.id);

  factory VariableOwner.environment(String id) =>
      VariableOwner._('environment', id);
  factory VariableOwner.collection(String id) =>
      VariableOwner._('collection', id);
  factory VariableOwner.folder(String id) => VariableOwner._('folder', id);
  static const global = VariableOwner._('global', '');

  final String kind;
  final String id;
}
