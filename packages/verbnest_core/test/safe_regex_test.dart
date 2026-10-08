import 'package:test/test.dart';
import 'package:verbnest_core/src/safe_regex.dart';

void main() {
  test('plain patterns match', () {
    expect(safeRegexMatch(r'^a+b$', 'aaab'), isTrue);
    expect(safeRegexMatch(r'^a+b$', 'c'), isFalse);
  });

  test('nested quantifiers, long and invalid patterns are refused', () {
    expect(safeRegexMatch(r'(a+)+$', 'aaaaaaaaaaaaaaaaaaaaaaaaaaaa!'), isNull);
    expect(safeRegexMatch('a' * 501, 'a'), isNull);
    expect(safeRegexMatch('(', 'a'), isNull);
  });
}
