import 'package:verbnest_core/verbnest_core.dart';
import 'package:test/test.dart';

void main() {
  test('is 26 valid characters and unique', () {
    final ids = {for (var i = 0; i < 1000; i++) Ulid.generate()};
    expect(ids, hasLength(1000));
    expect(ids.every(Ulid.isValid), isTrue);
  });

  test('sorts by creation time', () {
    final a = Ulid.generate(now: DateTime.utc(2026, 1, 1));
    final b = Ulid.generate(now: DateTime.utc(2026, 1, 2));
    expect(a.compareTo(b), lessThan(0));
  });

  test('rejects malformed ids', () {
    expect(Ulid.isValid('short'), isFalse);
    expect(Ulid.isValid('I' * 26), isFalse);
  });
}
