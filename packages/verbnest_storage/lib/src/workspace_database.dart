import 'dart:async';
import 'dart:io';

import 'package:sqlite3/sqlite3.dart';

import 'errors.dart';
import 'workspace_schema.dart';

/// An open workspace database (ADR-007). Owns the SQLite handle, enforces the
/// single-writer lock and runs migrations.
class WorkspaceDatabase {
  WorkspaceDatabase._(this.db, this.path);

  final Database db;

  /// File path, or null for an in-memory database.
  final String? path;

  final _changes = StreamController<void>.broadcast(sync: true);

  /// Fires after every committed write.
  Stream<void> get changes => _changes.stream;

  void notifyChanged() => _changes.add(null);

  static WorkspaceDatabase memory() {
    final db = sqlite3.openInMemory();
    final ws = WorkspaceDatabase._(db, null);
    ws._configure();
    ws._initialise();
    return ws;
  }

  /// Opens [path]. With [create] a missing or empty file becomes a new
  /// workspace; otherwise a missing file is an error.
  static WorkspaceDatabase open(String path, {bool create = false}) {
    if (!create && !File(path).existsSync()) throw NotFoundError(path);
    final Database db;
    try {
      db = sqlite3.open(path);
    } on SqliteException catch (e) {
      throw _translate(e, path);
    }
    final ws = WorkspaceDatabase._(db, path);
    try {
      ws._configure(exclusive: true);
      ws._prepare(create: create);
    } on SqliteException catch (e) {
      db.close();
      throw _translate(e, path);
    } catch (_) {
      db.close();
      rethrow;
    }
    return ws;
  }

  static StorageError _translate(SqliteException e, String path) {
    // 3 = PERM, 5 = BUSY, 6 = LOCKED, 8 = READONLY, 14 = CANTOPEN,
    // 23 = AUTH, 26 = NOTADB
    return switch (e.resultCode) {
      5 || 6 => WorkspaceLockedError(path),
      3 || 8 || 14 || 23 => WorkspaceAccessError(path),
      _ => NotAWorkspaceError(path),
    };
  }

  void _configure({bool exclusive = false}) {
    if (exclusive) db.execute('PRAGMA locking_mode = EXCLUSIVE');
    db.execute('PRAGMA journal_mode = WAL');
    db.execute('PRAGMA foreign_keys = ON');
  }

  void _prepare({required bool create}) {
    final appId = _pragma('application_id');
    final hasTables = db
        .select('SELECT 1 FROM sqlite_master LIMIT 1')
        .isNotEmpty;
    if (appId == 0 && !hasTables) {
      if (!create) throw NotAWorkspaceError(path ?? ':memory:');
      _initialise();
      return;
    }
    if (appId != workspaceApplicationId) {
      throw NotAWorkspaceError(path ?? ':memory:');
    }
    _upgrade();
  }

  void _initialise() {
    db.execute('PRAGMA application_id = $workspaceApplicationId');
    _migrate(from: 0);
  }

  void _upgrade() {
    final found = _pragma('user_version');
    if (found > workspaceSchemaVersion) {
      throw UnsupportedSchemaError(found, workspaceSchemaVersion);
    }
    if (found == workspaceSchemaVersion) return;
    _backup(found);
    _migrate(from: found);
  }

  /// Copies the file before an upgrade so a bad migration is recoverable.
  void _backup(int version) {
    final p = path;
    if (p == null) return;
    db.execute('PRAGMA wal_checkpoint(TRUNCATE)');
    File(p).copySync('$p.bak-v$version');
  }

  void _migrate({required int from}) {
    db.execute('BEGIN');
    try {
      for (var v = from; v < workspaceSchemaVersion; v++) {
        db.execute(workspaceMigrations[v]);
      }
      db.execute('PRAGMA user_version = $workspaceSchemaVersion');
      db.execute('COMMIT');
    } catch (_) {
      db.execute('ROLLBACK');
      rethrow;
    }
  }

  int _pragma(String name) =>
      (db.select('PRAGMA $name').first.values.first as int?) ?? 0;

  int get schemaVersion => _pragma('user_version');

  /// Runs [body] in a transaction; any exception rolls everything back, so a
  /// failed multi-row edit leaves no partial state (NFR-REL-001).
  ///
  /// Re-entrant: a call made inside another transaction joins it, and only
  /// the outermost call commits, rolls back and notifies listeners.
  T transaction<T>(T Function() body) {
    if (_depth > 0) return body();
    db.execute('BEGIN IMMEDIATE');
    _depth++;
    final T result;
    try {
      result = body();
      db.execute('COMMIT');
    } catch (_) {
      db.execute('ROLLBACK');
      rethrow;
    } finally {
      _depth--;
    }
    notifyChanged();
    return result;
  }

  int _depth = 0;

  /// Writes a consistent copy with no history or secret variables
  /// (FR-WS-007): history lives in the local store and secret variables in
  /// the secret store. Literal credentials typed into auth fields are part
  /// of the workspace and are copied; share the file accordingly.
  void exportCopy(String destination) {
    if (File(destination).existsSync()) {
      throw InvalidOperationError('$destination already exists');
    }
    db.execute('VACUUM INTO ?', [destination]);
  }

  void close() {
    _changes.close();
    db.close();
  }
}
