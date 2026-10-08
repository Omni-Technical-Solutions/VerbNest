import 'dart:convert';
import 'dart:typed_data';

import 'package:verbnest_core/verbnest_core.dart';
import 'package:sqlite3/sqlite3.dart';

import 'attachment_store.dart';
import 'errors.dart';
import 'models.dart';
import 'repository_models.dart';
import 'row_mapper.dart';
import 'search_documents.dart';
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
    return rows.isEmpty ? null : rows.first.str('value');
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
    return [for (final r in rows.skip(1)) r.str('id')];
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
    final max = rows.first.integerOrNull('p');
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
    final kind = NodeKind.values.byName(row.str('kind'));
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

  /// Pre-request and post-response scripts of a collection or folder.
  Scripts containerScripts(String id) =>
      Scripts.fromJson(_decodeOrNull(_row(id)['scripts_json']));

  void setContainerScripts(String id, Scripts scripts) => _ws.transaction(() {
    _row(id);
    _db.execute(
      'UPDATE node SET scripts_json = ?, updated_at = ? WHERE id = ?',
      [jsonEncode(scripts.toJson()), _now, id],
    );
  });

  /// Scripts of the containers above [id], collection first, then folders.
  /// The order scripts run in (FR-SCR-001).
  List<Scripts> scriptsChain(String id) => [
    for (final a in ancestors(id).reversed) containerScripts(a),
  ];

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
      name: r.str('name'),
      data: _decode(r['data']),
      auth: _decodeOrNull(r['auth_json']),
      scripts: _decodeOrNull(r['scripts_json']),
      description: r.str('description'),
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
    final rev = last.isEmpty ? 1 : (last.first.integer('rev')) + 1;
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
        rev: r.integer('rev'),
        savedAt: DateTime.fromMillisecondsSinceEpoch(r.integer('saved_at')),
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
        key: r.str('key'),
        value: (r.strOrNull('value')) ?? '',
        secret: r['type'] == 'secret',
        enabled: r.flag('enabled'),
        description: r.str('description'),
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
        id: r.str('id'),
        name: r.str('name'),
        color: r.strOrNull('color'),
        variables: variables(VariableOwner.environment(r.str('id'))),
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

  // ---- favourites (FR-COL-004) --------------------------------------------

  bool isFavourite(String id) =>
      _decode(_row(id)['extra'])['favourite'] == true;

  void setFavourite(String id, bool value) => _ws.transaction(() {
    final extra = _decode(_row(id)['extra']);
    if (value) {
      extra['favourite'] = true;
    } else {
      extra.remove('favourite');
    }
    _db.execute('UPDATE node SET extra = ? WHERE id = ?', [
      jsonEncode(extra),
      id,
    ]);
  });

  /// Ids of favourite requests, in tree order of their ids.
  List<String> favourites() => [
    for (final r in _db.select(
      "SELECT id FROM node WHERE kind = 'request' "
      "AND json_extract(extra, '\$.favourite') = 1 ORDER BY name, id",
    ))
      r.str('id'),
  ];

  // ---- saved examples (FR-COL-005) -----------------------------------------

  List<ExampleInfo> examples(String requestId) => [
    for (final r in _db.select(
      'SELECT * FROM example WHERE request_id = ? ORDER BY position, id',
      [requestId],
    ))
      _example(r),
  ];

  ExampleInfo example(String id) {
    final rows = _db.select('SELECT * FROM example WHERE id = ?', [id]);
    if (rows.isEmpty) throw NotFoundError('Example $id');
    return _example(rows.first);
  }

  ExampleInfo _example(Row r) => ExampleInfo(
    id: r.str('id'),
    requestId: r.str('request_id'),
    name: r.str('name'),
    data: _decode(r['data']),
    body: (r['body_blob'] as Uint8List?) ?? Uint8List(0),
  );

  /// Adds a saved response for [requestId] and returns its id. [data] holds
  /// `status`, `reason`, `headers` and optionally `request`.
  String addExample(String requestId, String name, Json data, Uint8List body) =>
      _ws.transaction(() {
        _row(requestId);
        return restoreExample(
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
  String restoreExample(ExampleInfo e) => _ws.transaction(() {
    final old = _db.select('SELECT position FROM example WHERE id = ?', [e.id]);
    final pos = old.isNotEmpty
        ? old.first.integer('position')
        : ((_db.select(
                        'SELECT MAX(position) AS p FROM example WHERE request_id = ?',
                        [e.requestId],
                      ).first['p']
                      as int?) ??
                  0) +
              _step;
    _db.execute(
      'INSERT INTO example(id, request_id, name, position, data, body_blob) '
      'VALUES (?, ?, ?, ?, ?, ?) ON CONFLICT(id) DO UPDATE SET '
      'name = excluded.name, data = excluded.data, body_blob = excluded.body_blob',
      [e.id, e.requestId, e.name, pos, jsonEncode(e.data), e.body],
    );
    return e.id;
  });

  void renameExample(String id, String name) => _ws.transaction(
    () => _db.execute('UPDATE example SET name = ? WHERE id = ?', [name, id]),
  );

  void deleteExample(String id) => _ws.transaction(
    () => _db.execute('DELETE FROM example WHERE id = ?', [id]),
  );

  // ---- snapshot support (FR-WS-006) -----------------------------------------

  bool hasNode(String id) =>
      _db.select('SELECT 1 FROM node WHERE id = ?', [id]).isNotEmpty;

  /// Everything stored on a node, decoded, for the YAML snapshot.
  Json rawNode(String id) {
    final r = _row(id);
    return {
      'id': id,
      'kind': r['kind'],
      'type': r['type'],
      'name': r['name'],
      'description': r['description'],
      'auth': _decodeOrNull(r['auth_json']),
      'scripts': _decodeOrNull(r['scripts_json']),
      'data': _decode(r['data']),
      'extra': _decode(r['extra']),
    };
  }

  /// Inserts a node with the id it was exported with. The position follows
  /// the order of calls under the same parent.
  void restoreNode(Json n, String? parentId) => _ws.transaction(() {
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

  /// Ids of every stored attachment.
  List<String> attachmentIds() => [
    for (final r in _db.select('SELECT id FROM attachment ORDER BY id'))
      r.str('id'),
  ];

  void restoreAttachment(
    String id,
    String name,
    String? mime,
    Uint8List b,
  ) => _ws.transaction(
    () => _db.execute(
      'INSERT OR IGNORE INTO attachment(id, name, mime, content, created_at) '
      'VALUES (?, ?, ?, ?, ?)',
      [id, name, mime, b, _now],
    ),
  );

  /// Replaces the workspace id (a snapshot import into a new workspace).
  void restoreWorkspaceId(String id) => setMeta('workspace_id', id);

  // ---- helpers ----------------------------------------------------------

  Row _row(String id) {
    final rows = _db.select(
      "SELECT *, json_extract(data, '\$.method') AS method FROM node WHERE id = ?",
      [id],
    );
    if (rows.isEmpty) throw NotFoundError('Item $id');
    return rows.first;
  }

  NodeInfo _info(Row r) => NodeInfo(
    id: r.str('id'),
    parentId: r.strOrNull('parent_id'),
    kind: NodeKind.values.byName(r.str('kind')),
    type: r.strOrNull('type'),
    name: r.str('name'),
    position: r.integer('position'),
    method: r.strOrNull('method'),
  );

  // ---- attachments (files kept inside the workspace) -----------------------

  late final AttachmentStore _attachments = AttachmentStore(_db, _clock);

  /// Stores [bytes] and returns the attachment id.
  String addAttachment(String name, Uint8List bytes, {String? mime}) =>
      _attachments.add(name, bytes, mime: mime);

  AttachmentInfo? attachment(String id) => _attachments.info(id);

  Uint8List attachmentBytes(String id) => _attachments.bytes(id);

  void deleteAttachment(String id) => _attachments.delete(id);

  /// Deletes attachments that no request, example or revision mentions.
  int pruneUnreferencedAttachments() => _attachments.pruneUnreferenced();

  /// Deletes every attachment not named in [referenced]. Returns the count.
  int pruneAttachments(Set<String> referenced) =>
      _attachments.prune(referenced);

  // ---- search documents ------------------------------------------------

  /// Text of every node for [SearchIndex]. Header values are not included.
  List<SearchDoc> searchDocuments() => readSearchDocuments(_db);

  Json _decode(Object? text) =>
      (jsonDecode(text as String) as Map).cast<String, Object?>();

  Json? _decodeOrNull(Object? text) => text == null ? null : _decode(text);
}
