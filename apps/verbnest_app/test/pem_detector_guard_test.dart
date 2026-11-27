import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Whether a file is a PEM is decided in one place, `looksLikePem` in
/// `verbnest_http`. Five copies once looked only at the first 80 or 200 bytes,
/// so a certificate with text before its first block was a PEM to one and not
/// to another (the dialog asked for a private key it gave no way to choose).
void main() {
  test('no code decides "is a PEM" from the start of the file', () {
    final root = Directory('../..');
    final dirs = [
      Directory('lib'),
      for (final d in Directory('${root.path}/packages').listSync())
        if (d is Directory) Directory('${d.path}/lib'),
    ];
    final offenders = <String>[];
    for (final dir in dirs.where((d) => d.existsSync())) {
      for (final f in dir.listSync(recursive: true).whereType<File>()) {
        if (!f.path.endsWith('.dart')) continue;
        final lines = f.readAsLinesSync();
        for (var i = 0; i < lines.length; i++) {
          if (!lines[i].contains('-----BEGIN')) continue;
          final near = lines
              .sublist(
                i > 2 ? i - 2 : 0,
                i + 3 > lines.length ? lines.length : i + 3,
              )
              .join('\n');
          if (RegExp(r'\.take\(\d+\)|\.sublist\(0, ?\d+\)').hasMatch(near)) {
            offenders.add('${f.path}:${i + 1}');
          }
        }
      }
    }
    expect(offenders, isEmpty, reason: 'use looksLikePem from verbnest_http');
  });
}
