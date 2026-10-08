import 'package:sqlite3/sqlite3.dart';
import 'package:test/test.dart';
import 'package:verbnest_storage/src/row_mapper.dart';
import 'package:verbnest_storage/verbnest_storage.dart';

void main() {
  final db = sqlite3.openInMemory();
  tearDown(() => db.close());

  test('typed reads, and a wrong type names the column', () {
    final r = db.select("SELECT 'a' AS s, 3 AS n, NULL AS z, 1 AS f").first;
    expect(r.str('s'), 'a');
    expect(r.integer('n'), 3);
    expect(r.strOrNull('z'), isNull);
    expect(r.flag('f'), isTrue);
    expect(
      () => r.integer('s'),
      throwsA(
        isA<StorageFormatError>().having(
          (e) => e.message,
          'message',
          contains('"s"'),
        ),
      ),
    );
    expect(() => r.str('z'), throwsA(isA<StorageFormatError>()));
  });
}
