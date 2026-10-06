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
    for (final bad in ['../x.yaml', '/abs.yaml', 'a/../../b.yaml', 'a//b']) {
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
}
