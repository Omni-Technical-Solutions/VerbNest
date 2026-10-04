import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:postit_storage/postit_storage.dart';

/// Everything tied to the open workspace: its database, the repository over
/// it and the device-local store.
class WorkspaceSession {
  WorkspaceSession({
    required this.db,
    required this.repo,
    required this.local,
    SecretStore? secrets,
  }) : secrets = secrets ?? LocalDbSecretStore(local);

  final WorkspaceDatabase db;
  final WorkspaceRepository repo;
  final LocalStore local;
  final SecretStore secrets;

  /// In-memory session for tests and previews.
  factory WorkspaceSession.memory() {
    final db = WorkspaceDatabase.memory();
    return WorkspaceSession(
      db: db,
      repo: WorkspaceRepository(db),
      local: LocalStore.memory(),
    );
  }

  /// Opens (creating if needed) the default workspace in app storage
  /// (FR-WS-001: no folder permission needed).
  static Future<WorkspaceSession> openDefault() async {
    final docs = await getApplicationDocumentsDirectory();
    final support = await getApplicationSupportDirectory();
    final dir = Directory(p.join(docs.path, 'PostIt', 'workspaces'))
      ..createSync(recursive: true);
    Directory(support.path).createSync(recursive: true);

    final db = WorkspaceDatabase.open(
      p.join(dir.path, 'default.postit'),
      create: true,
    );
    final repo = WorkspaceRepository(db);
    final local = LocalStore.open(p.join(support.path, 'local.db'));
    local.touchWorkspace(repo.workspaceId, repo.name, db.path!);
    return WorkspaceSession(db: db, repo: repo, local: local);
  }

  void close() {
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
