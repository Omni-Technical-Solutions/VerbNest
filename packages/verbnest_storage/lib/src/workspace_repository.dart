import 'dart:convert';
import 'dart:typed_data';

import 'package:verbnest_core/verbnest_core.dart';
import 'package:sqlite3/sqlite3.dart';

import 'attachment_store.dart';
import 'environment_store.dart';
import 'errors.dart';
import 'example_store.dart';
import 'models.dart';
import 'repository_models.dart';
import 'revision_store.dart';
import 'row_mapper.dart';
import 'search_documents.dart';
import 'tree_store.dart';
import 'workspace_database.dart';

import 'store_support.dart' show Json;

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

  late final TreeStore _tree = TreeStore(_ws, _clock);

  List<NodeInfo> children(String? parentId) => _tree.children(parentId);

  NodeInfo node(String id) => _tree.node(id);

  /// Every ancestor id from the parent up to the collection.
  List<String> ancestors(String id) => _tree.ancestors(id);

  String createCollection(String name) =>
      _tree.create(null, NodeKind.collection, name);

  String createFolder(String parentId, String name) =>
      _tree.create(parentId, NodeKind.folder, name);

  /// Creates a request under [parentId]; the id of [draft] is ignored and a
  /// fresh one is generated.
  String createRequest(String parentId, HttpRequestItem draft) {
    final id = _tree.create(
      parentId,
      NodeKind.request,
      draft.name,
      type: 'http',
    );
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

  void rename(String id, String name) => _tree.rename(id, name);

  void delete(String id) => _tree.delete(id);

  /// Moves [id] under [newParentId] at [index] among its new siblings.
  void move(String id, String? newParentId, int index) =>
      _tree.move(id, newParentId, index);

  /// Deep-copies [id] next to the original; returns the new root id.
  String duplicate(String id) => _tree.duplicate(id);

  Row _row(String id) => _tree.byId(id);

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

  late final RevisionStore _revisions = RevisionStore(
    _db,
    () => _now,
    maxRevisions,
  );

  void _addRevision(String id, String snapshot) => _revisions.add(id, snapshot);

  List<RevisionInfo> revisions(String id) => _revisions.list(id);

  /// The request as it was at [rev].
  HttpRequestItem revision(String id, int rev) => _revisions.at(id, rev);

  /// Makes [rev] the current version; recorded as a new revision.
  void restoreRevision(String id, int rev) => saveRequest(revision(id, rev));

  // ---- variables and environments ----------------------------------------

  late final EnvironmentStore _environments = EnvironmentStore(_ws, _clock);

  List<Variable> variables(VariableOwner owner) =>
      _environments.variables(owner);

  /// Replaces all variables of [owner]. Secret values are never stored
  /// (constitution II.4); they belong in the secret store.
  void saveVariables(VariableOwner owner, List<Variable> vars) =>
      _environments.saveVariables(owner, vars);

  List<Environment> environments() => _environments.environments();

  Environment environment(String id) => _environments.environment(id);

  /// Inserts or updates [env] together with its variables.
  void saveEnvironment(Environment env) => _environments.saveEnvironment(env);

  void deleteEnvironment(String id) => _ws.transaction(() {
    _environments.delete(id);
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

  late final ExampleStore _examples = ExampleStore(_ws, _clock, _row);

  List<ExampleInfo> examples(String requestId) =>
      _examples.forRequest(requestId);

  ExampleInfo example(String id) => _examples.get(id);

  /// Adds a saved response for [requestId] and returns its id. [data] holds
  /// `status`, `reason`, `headers` and optionally `request`.
  String addExample(String requestId, String name, Json data, Uint8List body) =>
      _examples.add(requestId, name, data, body);

  /// Inserts or replaces an example keeping its id.
  String restoreExample(ExampleInfo e) => _examples.restore(e);

  void renameExample(String id, String name) => _examples.rename(id, name);

  void deleteExample(String id) => _examples.delete(id);

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
  void restoreNode(Json n, String? parentId) => _tree.restore(n, parentId);

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
