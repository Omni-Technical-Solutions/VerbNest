import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:postit_storage/postit_storage.dart';

import 'secure_vault.dart';

/// Everything tied to the open workspace: its database, the repository over
/// it and the device-local store.
class WorkspaceSession {
  WorkspaceSession({
    required this.db,
    required this.repo,
    required this.local,
    SecretStore? secrets,
    this.secretsProtected = false,
  }) : secrets = secrets ?? LocalDbSecretStore(local);

  final WorkspaceDatabase db;
  final WorkspaceRepository repo;
  final LocalStore local;
  final SecretStore secrets;

  /// True when secrets live in the OS secret store. False means the
  /// unencrypted device-local fallback is in use.
  final bool secretsProtected;

  /// Non-secret current values: device-local, never in the workspace file.
  /// Stored under a `current:` scope so they are not mistaken for secrets.
  Map<String, String> currentOverrides(String kind, String id) =>
      local.currentValues(repo.workspaceId, 'current:$kind', id);

  void setCurrentOverride(String kind, String id, String key, String value) =>
      value.isEmpty
      ? local.clearCurrentValue(repo.workspaceId, 'current:$kind', id, key)
      : local.setCurrentValue(
          repo.workspaceId,
          'current:$kind',
          id,
          key,
          value,
        );

  /// In-memory session for tests and previews.
  factory WorkspaceSession.memory() {
    final db = WorkspaceDatabase.memory();
    final repo = WorkspaceRepository(db);
    // Created on first read otherwise, which would write during a build.
    repo.workspaceId;
    return WorkspaceSession(db: db, repo: repo, local: LocalStore.memory());
  }

  /// Folder holding the workspace files (FR-WS-001: no permission needed).
  static Future<Directory> workspacesDir() async {
    final docs = await getApplicationDocumentsDirectory();
    return Directory(p.join(docs.path, 'PostIt', 'workspaces'))
      ..createSync(recursive: true);
  }

  /// Opens the most recently used workspace whose file still exists, or the
  /// default one (created if needed).
  static Future<WorkspaceSession> openDefault({SecretVault? vault}) async {
    final dir = await workspacesDir();
    final support = await getApplicationSupportDirectory();
    Directory(support.path).createSync(recursive: true);
    final local = LocalStore.open(p.join(support.path, 'local.db'));
    final recent = local
        .recentWorkspaces()
        .where((w) => File(w.dbPath).existsSync())
        .firstOrNull;
    local.close();
    return openFile(
      recent?.dbPath ?? p.join(dir.path, 'default.postit'),
      create: recent == null,
      vault: vault,
    );
  }

  /// Opens the workspace file at [path]. Throws a `StorageError` when it is
  /// missing, locked, not a workspace, or from a newer app.
  static Future<WorkspaceSession> openFile(
    String path, {
    bool create = false,
    SecretVault? vault,
  }) async {
    final support = await getApplicationSupportDirectory();
    Directory(support.path).createSync(recursive: true);
    final db = WorkspaceDatabase.open(path, create: create);
    final repo = WorkspaceRepository(db);
    final local = LocalStore.open(p.join(support.path, 'local.db'));
    local.touchWorkspace(repo.workspaceId, repo.name, db.path!);
    repo.pruneUnreferencedAttachments();
    final fallback = LocalDbSecretStore(local);
    final v = vault ?? PlatformSecretVault();
    if (await vaultWorks(v)) {
      final store = await VaultSecretStore.load(v, repo.workspaceId);
      final owners = local.secretOwners(repo.workspaceId);
      migrateSecrets(
        fallback,
        store,
        repo.workspaceId,
        owners,
        removeSource: false,
      );
      await store.flush();
      // Keep the old copy until the platform store confirmed the write.
      if (store.lastError == null) {
        removeSecrets(fallback, repo.workspaceId, owners);
      }
      return WorkspaceSession(
        db: db,
        repo: repo,
        local: local,
        secrets: store,
        secretsProtected: store.lastError == null,
      );
    }
    return WorkspaceSession(db: db, repo: repo, local: local);
  }

  SearchIndex? _searchIndex;

  /// Full-text search over this workspace; call `rebuild()` before use.
  SearchIndex get searchIndex => _searchIndex ??= SearchIndex(repo);

  void close() {
    _searchIndex?.dispose();
    db.close();
    local.close();
  }
}

/// Must be overridden in `ProviderScope` with the opened session.
final sessionProvider = Provider<WorkspaceSession>(
  (ref) => throw UnimplementedError('sessionProvider must be overridden'),
);

final repositoryProvider = Provider<WorkspaceRepository>(
  (ref) => ref.watch(sessionProvider).repo,
);
