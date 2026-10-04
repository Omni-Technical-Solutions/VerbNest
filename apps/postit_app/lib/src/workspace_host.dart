import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;
import 'package:postit_core/postit_core.dart';
import 'package:postit_storage/postit_storage.dart';

import 'state/session.dart';

/// Open, create, import, export and switch workspaces. The host swaps the
/// whole provider scope, so tabs and drafts of the old workspace are dropped.
abstract interface class WorkspaceSwitcher {
  List<RecentWorkspace> recent();
  Future<void> open(String path);
  Future<void> create(String name);

  /// Copies [bytes] into the workspaces folder and opens it. Rejects files
  /// that are not workspaces.
  Future<void> importBytes(String fileName, Uint8List bytes);

  /// A consistent copy of the open workspace (no history or secrets).
  Future<Uint8List> exportCurrent();
}

final workspaceSwitcherProvider = Provider<WorkspaceSwitcher>(
  (ref) => throw UnimplementedError('No workspace host above this widget'),
);

String uniqueWorkspacePath(Directory dir, String name) {
  final base = name
      .trim()
      .replaceAll(RegExp(r'[^\w\- ]+'), '_')
      .replaceAll(RegExp(r'\s+'), ' ');
  final stem = base.isEmpty ? 'workspace' : base;
  var path = p.join(dir.path, '$stem.postit');
  for (var n = 2; File(path).existsSync(); n++) {
    path = p.join(dir.path, '$stem $n.postit');
  }
  return path;
}

class WorkspaceHost extends StatefulWidget {
  const WorkspaceHost({super.key, required this.initial, required this.child});

  final WorkspaceSession initial;
  final Widget child;

  @override
  State<WorkspaceHost> createState() => _WorkspaceHostState();
}

class _WorkspaceHostState extends State<WorkspaceHost>
    implements WorkspaceSwitcher {
  late WorkspaceSession _session = widget.initial;

  Future<void> _swap(WorkspaceSession next) async {
    final old = _session;
    setState(() => _session = next);
    // Close after the new scope is built so nothing reads a closed database.
    WidgetsBinding.instance.addPostFrameCallback((_) => old.close());
  }

  @override
  List<RecentWorkspace> recent() => [
    for (final w in _session.local.recentWorkspaces())
      if (File(w.dbPath).existsSync()) w,
  ];

  @override
  Future<void> open(String path) async {
    if (p.equals(path, _session.db.path ?? '')) return;
    await _swap(await WorkspaceSession.openFile(path));
  }

  @override
  Future<void> create(String name) async {
    final dir = await WorkspaceSession.workspacesDir();
    final path = uniqueWorkspacePath(dir, name);
    final next = await WorkspaceSession.openFile(path, create: true);
    next.repo.name = name.trim().isEmpty ? 'Workspace' : name.trim();
    next.local.touchWorkspace(next.repo.workspaceId, next.repo.name, path);
    await _swap(next);
  }

  @override
  Future<void> importBytes(String fileName, Uint8List bytes) async {
    final dir = await WorkspaceSession.workspacesDir();
    final path = uniqueWorkspacePath(dir, p.basenameWithoutExtension(fileName));
    File(path).writeAsBytesSync(bytes);
    try {
      // A copy keeps the id of its source. Two workspaces with one id would
      // share recent-list entries, history and secrets, so give it its own.
      final db = WorkspaceDatabase.open(path);
      try {
        WorkspaceRepository(db).setMeta('workspace_id', Ulid.generate());
      } finally {
        db.close();
      }
      await _swap(await WorkspaceSession.openFile(path));
    } catch (_) {
      File(path).deleteSync();
      rethrow;
    }
  }

  @override
  Future<Uint8List> exportCurrent() async {
    final tmp = Directory.systemTemp.createTempSync('postit_export');
    try {
      final out = p.join(tmp.path, 'export.postit');
      _session.db.exportCopy(out);
      return File(out).readAsBytesSync();
    } finally {
      tmp.deleteSync(recursive: true);
    }
  }

  @override
  void dispose() {
    _session.close();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ProviderScope(
      key: ObjectKey(_session),
      overrides: [
        sessionProvider.overrideWithValue(_session),
        workspaceSwitcherProvider.overrideWithValue(this),
      ],
      child: widget.child,
    );
  }
}
