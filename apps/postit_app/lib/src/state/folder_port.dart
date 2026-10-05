import 'dart:io';

import 'package:file_selector/file_selector.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;

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

class PluginFolderPort implements FolderPort {
  const PluginFolderPort();

  @override
  bool get available =>
      Platform.isMacOS || Platform.isWindows || Platform.isLinux;

  @override
  Future<bool> write(Map<String, List<int>> files) async {
    final dir = await getDirectoryPath();
    if (dir == null) return false;
    for (final e in files.entries) {
      final f = File(p.joinAll([dir, ...e.key.split('/')]));
      f.parent.createSync(recursive: true);
      f.writeAsBytesSync(e.value);
    }
    return true;
  }

  @override
  Future<Map<String, List<int>>?> read() async {
    final dir = await getDirectoryPath();
    if (dir == null) return null;
    final out = <String, List<int>>{};
    for (final f in Directory(dir).listSync(recursive: true)) {
      if (f is! File) continue;
      final rel = p.relative(f.path, from: dir).replaceAll(r'\', '/');
      out[rel] = f.readAsBytesSync();
    }
    return out;
  }
}

final folderPortProvider = Provider<FolderPort>(
  (ref) => const PluginFolderPort(),
);
