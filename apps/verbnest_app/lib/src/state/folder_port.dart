import 'dart:io';

import 'package:file_selector/file_selector.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;

/// Largest single file read from a snapshot folder; attachments can be big,
/// but a runaway file should not exhaust memory.
const maxSnapshotFileBytes = 256 * 1024 * 1024;

/// Reads and writes a whole folder, for YAML snapshots (FR-WS-006). Only
/// desktop platforms have a folder chooser.
abstract interface class FolderPort {
  bool get available;

  /// Writes [files] (relative path to bytes) into a folder the user picks.
  /// False when cancelled.
  Future<bool> write(Map<String, List<int>> files);

  /// Reads every file under a folder the user picks; null when cancelled.
  Future<Map<String, List<int>>?> read();
}

/// Writes [files] under [dir]. Throws [ArgumentError] for a path that is
/// absolute or contains `..`, so a crafted name can never escape the folder.
void writeSnapshotFiles(String dir, Map<String, List<int>> files) {
  for (final e in files.entries) {
    final parts = e.key.split('/');
    if (e.key.startsWith('/') ||
        parts.any((s) => s == '..' || s == '.' || s.isEmpty)) {
      throw ArgumentError('Unsafe path in snapshot: ${e.key}');
    }
    final f = File(p.joinAll([dir, ...parts]));
    f.parent.createSync(recursive: true);
    f.writeAsBytesSync(e.value);
  }
}

class PluginFolderPort implements FolderPort {
  const PluginFolderPort();

  @override
  bool get available =>
      Platform.isMacOS || Platform.isWindows || Platform.isLinux;

  @override
  Future<bool> write(Map<String, List<int>> files) async {
    final dir = await getDirectoryPath();
    if (dir == null) return false;
    writeSnapshotFiles(dir, files);
    return true;
  }

  @override
  Future<Map<String, List<int>>?> read() async {
    final dir = await getDirectoryPath();
    if (dir == null) return null;
    final out = <String, List<int>>{};
    for (final f in Directory(
      dir,
    ).listSync(recursive: true, followLinks: false)) {
      if (f is! File) continue;
      if (f.lengthSync() > maxSnapshotFileBytes) {
        throw FormatException(
          '${p.basename(f.path)} is too large for a snapshot',
        );
      }
      final rel = p.relative(f.path, from: dir).replaceAll(r'\', '/');
      out[rel] = f.readAsBytesSync();
    }
    return out;
  }
}

final folderPortProvider = Provider<FolderPort>(
  (ref) => const PluginFolderPort(),
);
