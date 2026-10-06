import 'dart:io';

/// The folder the app used before it was renamed from PostIt to Verbnest, or
/// null when [support] does not look like a renamed folder. The platform
/// derives the folder from the bundle id (`com.omni.verbnest`, formerly
/// `com.omni.postit`) or, on Windows, from the product name.
String? legacySupportPath(String support) {
  final sep = Platform.pathSeparator;
  final i = support.lastIndexOf(sep);
  if (i < 0) return null;
  final name = support.substring(i + 1);
  final legacy = switch (name) {
    'com.omni.verbnest' => 'com.omni.postit',
    'Verbnest' => 'PostIt',
    'verbnest' => 'postit',
    _ => null,
  };
  return legacy == null ? null : '${support.substring(0, i + 1)}$legacy';
}

/// Copies the device-local data of the PostIt app (history, current values,
/// recent workspaces, settings) into [support] the first time the renamed app
/// starts. Does nothing when [support] already holds a `local.db`, when no old
/// folder exists, or when the old one has no `local.db`. The old folder is
/// left in place so the user can go back. Returns whether data was copied.
bool migrateLegacySupportDir(String support) {
  if (File('$support${Platform.pathSeparator}local.db').existsSync()) {
    return false;
  }
  final old = legacySupportPath(support);
  if (old == null) return false;
  final from = Directory(old);
  if (!File('$old${Platform.pathSeparator}local.db').existsSync()) return false;
  try {
    Directory(support).createSync(recursive: true);
    for (final e in from.listSync(recursive: true, followLinks: false)) {
      final rel = e.path.substring(from.path.length + 1);
      final target = '$support${Platform.pathSeparator}$rel';
      if (e is Directory) {
        Directory(target).createSync(recursive: true);
      } else if (e is File && !rel.endsWith('-wal') && !rel.endsWith('-shm')) {
        File(target).parent.createSync(recursive: true);
        e.copySync(target);
      }
    }
    return true;
  } on FileSystemException {
    return false;
  }
}
