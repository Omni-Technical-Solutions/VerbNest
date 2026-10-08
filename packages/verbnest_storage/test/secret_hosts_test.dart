import 'package:test/test.dart';
import 'package:verbnest_storage/verbnest_storage.dart';

class _Mem implements SecretStore {
  final m = <String, String>{};
  @override
  Map<String, String> values(String w, String k, String i) => {
    for (final e in m.entries)
      if (e.key.startsWith('$w|$k|$i|')) e.key.split('|').last: e.value,
  };
  @override
  void put(String w, String k, String i, String key, String v) =>
      m['$w|$k|$i|$key'] = v;
  @override
  void remove(String w, String k, String i, String key) =>
      m.remove('$w|$k|$i|$key');
}

void main() {
  final url = Uri.parse('https://API.example.com/x');

  test('nothing is allowed until approved, per secret and host', () {
    final h = SecretHosts(_Mem(), 'w');
    expect(h.blocked(['b', 'a'], url), ['a', 'b']);
    h.allow(['a'], 'api.EXAMPLE.com');
    expect(h.blocked(['a', 'b'], url), ['b']);
    expect(h.blocked(['a'], Uri.parse('https://evil.test/')), ['a']);
  });

  test('approvals are scoped to the workspace store', () {
    final store = _Mem();
    SecretHosts(store, 'w1').allow(['a'], 'api.example.com');
    expect(SecretHosts(store, 'w2').blocked(['a'], url), ['a']);
  });

  test('extra approvals and wildcards', () {
    final h = SecretHosts(
      _Mem(),
      'w',
      extra: {
        'a': {'api.example.com'},
        '*': {'other.test'},
      },
    );
    expect(h.blocked(['a'], url), isEmpty);
    expect(h.blocked(['z'], Uri.parse('http://other.test')), isEmpty);
    expect(h.blocked(['z'], url), ['z']);
    expect(
      SecretHosts(
        _Mem(),
        'w',
        extra: {
          '*': {'*'},
        },
      ).blocked(['z'], url),
      isEmpty,
    );
  });
}
