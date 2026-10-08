import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:verbnest_app/src/state/browser_port.dart';
import 'package:verbnest_app/src/state/folder_port.dart';

void main() {
  test('the browser opener refuses schemes other than http and https', () {
    final open = ProviderContainer().read(browserOpenerProvider);
    for (final u in ['file:///etc/passwd', 'ssh://host', 'myapp://x']) {
      expect(open(Uri.parse(u)), throwsA(isA<StateError>()));
    }
  });

  test('snapshot writing rejects paths that leave the chosen folder', () {
    final dir = Directory.systemTemp.createTempSync('verbnest-snap');
    addTearDown(() => dir.deleteSync(recursive: true));
    for (final bad in [
      '../x.yaml',
      '/abs.yaml',
      'a/../../b.yaml',
      'a//b',
      r'a\..\..\x.yaml',
      'C:/x.yaml',
      'a/C:x',
    ]) {
      expect(
        () => writeSnapshotFiles(dir.path, {
          bad: [1],
        }),
        throwsA(isA<ArgumentError>()),
        reason: bad,
      );
    }
    writeSnapshotFiles(dir.path, {
      'ok/a.yaml': [1, 2],
    });
    expect(File('${dir.path}/ok/a.yaml').readAsBytesSync(), [1, 2]);
  });

  test('snapshot writing does not follow a symlinked folder out', () {
    final dir = Directory.systemTemp.createTempSync('verbnest-snap');
    final outside = Directory.systemTemp.createTempSync('verbnest-out');
    addTearDown(() {
      dir.deleteSync(recursive: true);
      outside.deleteSync(recursive: true);
    });
    Link('${dir.path}/link').createSync(outside.path);
    expect(
      () => writeSnapshotFiles(dir.path, {
        'link/x.yaml': [1],
      }),
      throwsA(isA<ArgumentError>()),
    );
    expect(File('${outside.path}/x.yaml').existsSync(), isFalse);
  });

  test('snapshot writes refuse .git directories', () {
    final dir = Directory.systemTemp.createTempSync('vn_git');
    addTearDown(() => dir.deleteSync(recursive: true));
    expect(
      () => writeSnapshotFiles(dir.path, {
        '.git/hooks/pre-commit': [1],
      }),
      throwsA(isA<ArgumentError>()),
    );
  });
}
