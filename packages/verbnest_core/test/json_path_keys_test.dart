import 'package:test/test.dart';
import 'package:verbnest_core/verbnest_core.dart';

/// Keys with quotes, brackets and backslashes (found by the fuzz test: a
/// response with such a key used to make the results table throw).
void main() {
  test('a quoted key may hold quotes, brackets and backslashes', () {
    final doc = {
      "it's": 1,
      'a]b': 2,
      r'back\slash': 3,
      'sp ace': 4,
      'mix"\']\\': 5,
    };
    expect(jsonPath(doc, r"$['it\'s']"), [1]);
    expect(jsonPath(doc, r"$['a]b']"), [2]);
    expect(jsonPath(doc, r"$['back\\slash']"), [3]);
    expect(jsonPath(doc, r'$["sp ace"]'), [4]);
    expect(jsonPath(doc, r"$[ 'sp ace' ]"), [4]);
    // $['mix\"\'\]\\'] written without raw strings.
    expect(jsonPath(doc, '\$[\'mix\\"\\\'\\]\\\\\']'), [5]);
  });

  test('a quoted key that is not closed is a FormatException', () {
    for (final bad in [r"$['a", r"$['a'", r"$['a\']", r"$['a'x]", r"$[']"]) {
      expect(() => jsonPath({'a': 1}, bad), throwsFormatException, reason: bad);
    }
  });

  test('the table finds records under keys that need quoting', () {
    for (final key in ["r'ow", 'a]b', r'x\y', 'two words', '"q"', "a'b]c\\"]) {
      final body = {
        key: [
          {'id': 1},
          {'id': 2},
        ],
        'n': 2,
      };
      final sources = findTableSources(body);
      expect(sources.map((s) => s.count), [2], reason: key);
      final table = tableFromJson(body);
      expect(table, isNotNull, reason: key);
      expect(table!.rowCount, 2, reason: key);
      // The path it names is one jsonPath can resolve again.
      expect(jsonPath(body, sources.single.path), hasLength(1), reason: key);
    }
  });
}
