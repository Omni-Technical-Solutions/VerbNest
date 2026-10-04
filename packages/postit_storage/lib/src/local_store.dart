import 'dart:typed_data';

import 'package:sqlite3/sqlite3.dart';

/// `PRAGMA application_id` of the local database ("PLOC").
const localApplicationId = 0x504C4F43;

/// Forward-only migrations for the local database (data-model.md §4).
const localMigrations = <String>[
  '''
CREATE TABLE workspace (
  id TEXT PRIMARY KEY, name TEXT NOT NULL, db_path TEXT NOT NULL,
  last_opened_at INTEGER NOT NULL
);

CREATE TABLE history (
  id TEXT PRIMARY KEY, workspace_id TEXT NOT NULL, request_id TEXT,
  type TEXT NOT NULL, method TEXT NOT NULL, url TEXT NOT NULL,
  environment_name TEXT, sent_at INTEGER NOT NULL,
  status INTEGER, total_ms INTEGER,
  request_json TEXT NOT NULL, response_meta_json TEXT,
  response_body BLOB, body_truncated INTEGER NOT NULL DEFAULT 0, error TEXT
);
CREATE INDEX history_ws_time ON history(workspace_id, sent_at DESC);

CREATE TABLE variable_current (
  workspace_id TEXT NOT NULL, scope TEXT NOT NULL, scope_id TEXT NOT NULL,
  key TEXT NOT NULL, value TEXT NOT NULL,
  PRIMARY KEY (workspace_id, scope, scope_id, key)
);
''',
];

class HistoryEntry {
  HistoryEntry({
    required this.id,
    required this.workspaceId,
    this.requestId,
    this.type = 'http',
    required this.method,
    required this.url,
    this.environmentName,
    required this.sentAt,
    this.status,
    this.totalMs,
    required this.requestJson,
    this.responseMetaJson,
    this.responseBody,
    this.bodyTruncated = false,
    this.error,
  });

  final String id;
  final String workspaceId;
  final String? requestId;
  final String type;
  final String method;
  final String url;
  final String? environmentName;
  final DateTime sentAt;
  final int? status;
  final int? totalMs;

  /// The resolved request with secrets already masked.
  final String requestJson;
  final String? responseMetaJson;
  final Uint8List? responseBody;
  final bool bodyTruncated;
  final String? error;
}

/// Device-local state: history, current variable values and the recent
/// workspaces list. Losing this database never loses workspace content.
class LocalStore {
  LocalStore._(this._db);

  final Database _db;

  static LocalStore memory() => LocalStore._(sqlite3.openInMemory()).._init();

  static LocalStore open(String path) =>
      LocalStore._(sqlite3.open(path)).._init();

  void _init() {
    _db.execute('PRAGMA journal_mode = WAL');
    final version = _db.select('PRAGMA user_version').first.values.first as int;
    if (version > localMigrations.length) {
      // A newer app wrote this cache. It is disposable, so start fresh
      // rather than refusing to run.
      _reset();
    } else {
      _migrate(version);
    }
  }

  void _reset() {
    for (final r in _db.select(
      "SELECT name FROM sqlite_master WHERE type = 'table'",
    )) {
      _db.execute('DROP TABLE IF EXISTS "${r['name']}"');
    }
    _migrate(0);
  }

  void _migrate(int from) {
    if (from == localMigrations.length) return;
    _db.execute('BEGIN');
    try {
      for (var v = from; v < localMigrations.length; v++) {
        _db.execute(localMigrations[v]);
      }
      _db.execute('PRAGMA application_id = $localApplicationId');
      _db.execute('PRAGMA user_version = ${localMigrations.length}');
      _db.execute('COMMIT');
    } catch (_) {
      _db.execute('ROLLBACK');
      rethrow;
    }
  }

  void close() => _db.close();

  // ---- history ----------------------------------------------------------

  /// Stores [entry]. Bodies over [maxBodyBytes] are cut and flagged
  /// (FR-HIS-001); [storeBodies] false drops them entirely (FR-HIS-003).
  void addHistory(
    HistoryEntry entry, {
    int maxBodyBytes = 1024 * 1024,
    bool storeBodies = true,
  }) {
    var body = storeBodies ? entry.responseBody : null;
    var truncated = entry.bodyTruncated;
    if (body != null && body.length > maxBodyBytes) {
      body = Uint8List.sublistView(body, 0, maxBodyBytes);
      truncated = true;
    }
    _db.execute(
      'INSERT INTO history(id, workspace_id, request_id, type, method, url, '
      'environment_name, sent_at, status, total_ms, request_json, '
      'response_meta_json, response_body, body_truncated, error) '
      'VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)',
      [
        entry.id,
        entry.workspaceId,
        entry.requestId,
        entry.type,
        entry.method,
        entry.url,
        entry.environmentName,
        entry.sentAt.millisecondsSinceEpoch,
        entry.status,
        entry.totalMs,
        entry.requestJson,
        entry.responseMetaJson,
        body,
        truncated ? 1 : 0,
        entry.error,
      ],
    );
  }

  /// Newest first. [query] matches method, URL or status text.
  List<HistoryEntry> listHistory(
    String workspaceId, {
    String? query,
    int limit = 200,
    DateTime? before,
  }) {
    final where = StringBuffer('workspace_id = ?');
    final args = <Object?>[workspaceId];
    if (before != null) {
      where.write(' AND sent_at < ?');
      args.add(before.millisecondsSinceEpoch);
    }
    if (query != null && query.isNotEmpty) {
      where.write(
        " AND (url LIKE ? ESCAPE '\\' OR method LIKE ? ESCAPE '\\' OR CAST(status AS TEXT) = ?)",
      );
      final like =
          '%${query.replaceAll(r'\', r'\\').replaceAll('%', r'\%').replaceAll('_', r'\_')}%';
      args
        ..add(like)
        ..add(like)
        ..add(query);
    }
    args.add(limit);
    return [
      for (final r in _db.select(
        'SELECT * FROM history WHERE $where ORDER BY sent_at DESC, id DESC LIMIT ?',
        args,
      ))
        _entry(r),
    ];
  }

  HistoryEntry? history(String id) {
    final rows = _db.select('SELECT * FROM history WHERE id = ?', [id]);
    return rows.isEmpty ? null : _entry(rows.first);
  }

  void deleteHistory(String id) =>
      _db.execute('DELETE FROM history WHERE id = ?', [id]);

  void clearHistory(String workspaceId) =>
      _db.execute('DELETE FROM history WHERE workspace_id = ?', [workspaceId]);

  /// Applies retention (FR-HIS-003): keep at most [maxEntries], none older
  /// than [maxAge]. Returns the number of rows removed.
  int pruneHistory(
    String workspaceId, {
    int? maxEntries,
    Duration? maxAge,
    DateTime? now,
  }) {
    var removed = 0;
    if (maxAge != null) {
      final cutoff = (now ?? DateTime.now())
          .subtract(maxAge)
          .millisecondsSinceEpoch;
      _db.execute(
        'DELETE FROM history WHERE workspace_id = ? AND sent_at < ?',
        [workspaceId, cutoff],
      );
      removed += _db.updatedRows;
    }
    if (maxEntries != null) {
      _db.execute(
        'DELETE FROM history WHERE workspace_id = ? AND id NOT IN ('
        'SELECT id FROM history WHERE workspace_id = ? '
        'ORDER BY sent_at DESC, id DESC LIMIT ?)',
        [workspaceId, workspaceId, maxEntries],
      );
      removed += _db.updatedRows;
    }
    return removed;
  }

  HistoryEntry _entry(Row r) => HistoryEntry(
    id: r['id'] as String,
    workspaceId: r['workspace_id'] as String,
    requestId: r['request_id'] as String?,
    type: r['type'] as String,
    method: r['method'] as String,
    url: r['url'] as String,
    environmentName: r['environment_name'] as String?,
    sentAt: DateTime.fromMillisecondsSinceEpoch(r['sent_at'] as int),
    status: r['status'] as int?,
    totalMs: r['total_ms'] as int?,
    requestJson: r['request_json'] as String,
    responseMetaJson: r['response_meta_json'] as String?,
    responseBody: r['response_body'] as Uint8List?,
    bodyTruncated: (r['body_truncated'] as int) != 0,
    error: r['error'] as String?,
  );

  // ---- current variable values -------------------------------------------

  /// Current values for one scope owner, e.g. `('environment', envId)`.
  Map<String, String> currentValues(
    String workspaceId,
    String scope,
    String scopeId,
  ) => {
    for (final r in _db.select(
      'SELECT key, value FROM variable_current '
      'WHERE workspace_id = ? AND scope = ? AND scope_id = ?',
      [workspaceId, scope, scopeId],
    ))
      r['key'] as String: r['value'] as String,
  };

  void setCurrentValue(
    String workspaceId,
    String scope,
    String scopeId,
    String key,
    String value,
  ) => _db.execute(
    'INSERT INTO variable_current(workspace_id, scope, scope_id, key, value) '
    'VALUES (?, ?, ?, ?, ?) ON CONFLICT(workspace_id, scope, scope_id, key) '
    'DO UPDATE SET value = excluded.value',
    [workspaceId, scope, scopeId, key, value],
  );

  /// Distinct `(scope, scopeId)` pairs holding values, for migration.
  /// Scopes starting with `current:` are plain value overrides, not secrets.
  List<(String, String)> secretOwners(String workspaceId) => [
    for (final r in _db.select(
      'SELECT DISTINCT scope, scope_id FROM variable_current '
      "WHERE workspace_id = ? AND scope NOT LIKE 'current:%'",
      [workspaceId],
    ))
      (r['scope'] as String, r['scope_id'] as String),
  ];

  void clearCurrentValue(
    String workspaceId,
    String scope,
    String scopeId,
    String key,
  ) => _db.execute(
    'DELETE FROM variable_current '
    'WHERE workspace_id = ? AND scope = ? AND scope_id = ? AND key = ?',
    [workspaceId, scope, scopeId, key],
  );

  // ---- recent workspaces (FR-WS-002) --------------------------------------

  void touchWorkspace(String id, String name, String dbPath, {DateTime? now}) =>
      _db.execute(
        'INSERT INTO workspace(id, name, db_path, last_opened_at) VALUES (?, ?, ?, ?) '
        'ON CONFLICT(id) DO UPDATE SET name = excluded.name, '
        'db_path = excluded.db_path, last_opened_at = excluded.last_opened_at',
        [id, name, dbPath, (now ?? DateTime.now()).millisecondsSinceEpoch],
      );

  List<RecentWorkspace> recentWorkspaces({int limit = 20}) => [
    for (final r in _db.select(
      'SELECT * FROM workspace ORDER BY last_opened_at DESC LIMIT ?',
      [limit],
    ))
      RecentWorkspace(
        id: r['id'] as String,
        name: r['name'] as String,
        dbPath: r['db_path'] as String,
        lastOpenedAt: DateTime.fromMillisecondsSinceEpoch(
          r['last_opened_at'] as int,
        ),
      ),
  ];

  /// Removes the workspace from the list and drops its local state.
  void forgetWorkspace(String id) {
    _db.execute('DELETE FROM workspace WHERE id = ?', [id]);
    _db.execute('DELETE FROM history WHERE workspace_id = ?', [id]);
    _db.execute('DELETE FROM variable_current WHERE workspace_id = ?', [id]);
  }
}

class RecentWorkspace {
  const RecentWorkspace({
    required this.id,
    required this.name,
    required this.dbPath,
    required this.lastOpenedAt,
  });

  final String id;
  final String name;
  final String dbPath;
  final DateTime lastOpenedAt;
}
