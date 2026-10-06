import 'dart:io';

import 'package:test/test.dart';
import 'package:verbnest_storage/verbnest_storage.dart';

void main() {
  late Directory root;
  setUp(() => root = Directory.systemTemp.createTempSync('verbnest_mig'));
  tearDown(() => root.deleteSync(recursive: true));

  String p(String name) => '${root.path}${Platform.pathSeparator}$name';

  test('the old folder name follows from the new one', () {
    expect(legacySupportPath(p('com.omni.verbnest')), p('com.omni.postit'));
    expect(legacySupportPath(p('Verbnest')), p('PostIt'));
    expect(legacySupportPath(p('other')), isNull);
  });

  test('local data is copied once and the old folder is kept', () {
    final old = Directory(p('com.omni.postit'))..createSync();
    File('${old.path}/local.db').writeAsStringSync('db');
    Directory('${old.path}/sub').createSync();
    File('${old.path}/sub/x.txt').writeAsStringSync('x');
    File('${old.path}/local.db-wal').writeAsStringSync('wal');

    final support = p('com.omni.verbnest');
    expect(migrateLegacySupportDir(support), isTrue);
    expect(File('$support/local.db').readAsStringSync(), 'db');
    expect(File('$support/sub/x.txt').readAsStringSync(), 'x');
    expect(File('$support/local.db-wal').existsSync(), isFalse);
    expect(File('${old.path}/local.db').existsSync(), isTrue);

    File('$support/local.db').writeAsStringSync('new');
    expect(migrateLegacySupportDir(support), isFalse);
    expect(File('$support/local.db').readAsStringSync(), 'new');
  });

  test('nothing happens without an old folder', () {
    expect(migrateLegacySupportDir(p('com.omni.verbnest')), isFalse);
  });
}
