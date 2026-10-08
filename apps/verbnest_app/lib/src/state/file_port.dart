import 'dart:io' show Platform;
import 'dart:typed_data';

import 'package:file_selector/file_selector.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:share_plus/share_plus.dart';

export 'package:verbnest_runner/verbnest_runner.dart' show attachmentIdOf;

class PickedFile {
  const PickedFile(this.name, this.bytes, {this.mime});

  final String name;
  final Uint8List bytes;
  final String? mime;
}

/// File access the editor needs, behind an interface so tests and platforms
/// without a picker can swap it.
abstract interface class FilePort {
  /// Asks the user for a file; null when cancelled.
  Future<PickedFile?> pick();

  /// Saves [bytes] where the user chooses (desktop) or opens the share sheet
  /// (mobile). Returns false when cancelled.
  Future<bool> save(String suggestedName, Uint8List bytes, {String? mime});

  /// True when [save] opens a share sheet instead of a save dialog.
  bool get savesBySharing;
}

class PluginFilePort implements FilePort {
  const PluginFilePort();

  @override
  bool get savesBySharing => Platform.isAndroid || Platform.isIOS;

  @override
  Future<PickedFile?> pick() async {
    final f = await openFile();
    if (f == null) return null;
    return PickedFile(f.name, await f.readAsBytes(), mime: f.mimeType);
  }

  @override
  Future<bool> save(
    String suggestedName,
    Uint8List bytes, {
    String? mime,
  }) async {
    final file = XFile.fromData(bytes, name: suggestedName, mimeType: mime);
    if (savesBySharing) {
      final r = await SharePlus.instance.share(
        ShareParams(files: [file], fileNameOverrides: [suggestedName]),
      );
      return r.status != ShareResultStatus.dismissed;
    }
    final loc = await getSaveLocation(suggestedName: suggestedName);
    if (loc == null) return false;
    await file.saveTo(loc.path);
    return true;
  }
}

final filePortProvider = Provider<FilePort>((ref) => const PluginFilePort());

/// A file name that is safe to store and to use in a multipart header.
String safeFileName(String name) {
  final last = name
      .split(RegExp(r'[\\/]'))
      .last
      .replaceAll(RegExp(r'["\r\n]'), '_');
  return last.isEmpty ? 'file' : last;
}

/// Reference stored in a form-data file part: the attachment id plus the
/// file name, so the multipart `filename` is the real name.
String attachmentRef(String id, String name) =>
    'attachment:$id/${safeFileName(name)}';

/// A name for a saved response: from Content-Disposition, else the URL's last
/// segment, else `response` with an extension from the content type.
String responseFileName(
  List<(String, String)> headers,
  Uri url, {
  String? contentType,
}) {
  for (final h in headers) {
    if (h.$1.toLowerCase() != 'content-disposition') continue;
    final m = RegExp(
      r'''filename\*?=(?:UTF-8'')?"?([^";]+)"?''',
      caseSensitive: false,
    ).firstMatch(h.$2);
    if (m != null) return safeFileName(Uri.decodeComponent(m[1]!.trim()));
  }
  final last = url.pathSegments.where((s) => s.isNotEmpty).lastOrNull;
  if (last != null && last.contains('.')) return safeFileName(last);
  final ct = (contentType ?? '').split(';').first.trim().toLowerCase();
  final ext = switch (ct) {
    'application/json' => 'json',
    'text/html' => 'html',
    'text/plain' => 'txt',
    'application/xml' || 'text/xml' => 'xml',
    'image/png' => 'png',
    'image/jpeg' => 'jpg',
    'image/gif' => 'gif',
    'image/webp' => 'webp',
    'application/pdf' => 'pdf',
    _ => 'bin',
  };
  return '${last ?? 'response'}.$ext';
}
