import 'package:test/test.dart';
import 'package:verbnest_http/verbnest_http.dart';

void main() {
  test('a secret is hidden in its percent-encoded and JSON-escaped forms', () {
    final m = Masker(secretValues: ['a b&c"d']);
    final out = m.maskText(
      'raw a b&c"d url a%20b%26c%22d form a+b%26c%22d json a b&c\\"d',
    );
    expect(out, isNot(contains('a%20b')));
    expect(out, isNot(contains('a+b')));
    expect(out, isNot(contains('c\\"d')));
    expect(out, isNot(contains('a b&c"d')));
  });

  test('common credential headers are masked by default', () {
    final m = Masker();
    expect(m.isSensitiveHeader('X-Api-Key'), isTrue);
    expect(m.isSensitiveHeader('X-Trace'), isFalse);
  });
}
