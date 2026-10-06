import 'package:verbnest_core/verbnest_core.dart';
import 'package:verbnest_import/verbnest_import.dart';
import 'package:verbnest_import/src/shell_tokenizer.dart';
import 'package:test/test.dart';

void main() {
  test('tokenizer handles quotes, continuations and ANSI-C', () {
    expect(shellSplit("a 'b c' \"d \\\"e\\\"\" f\\ g"), [
      'a',
      'b c',
      'd "e"',
      'f g',
    ]);
    expect(shellSplit('a \\\n b'), ['a', 'b']);
    expect(shellSplit(r"$'x\ny'"), ['x\ny']);
    expect(() => shellSplit("'open"), throwsFormatException);
  });

  test('parses a typical JSON POST', () {
    final r = parseCurl('''
curl -X POST 'https://api.test/users/:id?a=1&b=2' \\
  -H 'Content-Type: application/json' \\
  -H "Authorization: Bearer abc" \\
  --data-raw '{"x":1}' -k -L
''');
    final i = r.item;
    expect(i.method, 'POST');
    expect(i.url, 'https://api.test/users/:id?a=1&b=2');
    expect(i.params.map((p) => p.key), ['a', 'b']);
    expect(i.pathVars.single.key, 'id');
    expect(i.auth, isA<BearerAuth>());
    expect((i.auth as BearerAuth).token, 'abc');
    expect(i.body, isA<RawBody>());
    expect((i.body as RawBody).language, RawBodyLanguage.json);
    expect(i.settings.verifyTls, false);
    expect(i.settings.followRedirects, true);
    expect(r.warnings, isEmpty);
  });

  test('method defaults, basic auth, forms and bundled flags', () {
    expect(parseCurl('curl example.com').item.method, 'GET');
    expect(parseCurl('curl -d a=1 example.com').item.method, 'POST');
    expect(parseCurl('curl -I example.com').item.method, 'HEAD');
    final u = parseCurl('curl -sSL -u me:pw example.com').item;
    expect((u.auth as BasicAuth).username, 'me');
    expect(u.settings.followRedirects, true);
    final f = parseCurl('curl -F a=1 -F file=@/tmp/x example.com').item;
    final fields = (f.body as FormDataBody).fields;
    expect(fields[1].type, KeyValueType.file);
    expect(fields[1].value, '/tmp/x');
    final x = parseCurl('curl -XPUT example.com').item;
    expect(x.method, 'PUT');
    final g = parseCurl('curl -G -d q=1 example.com').item;
    expect(g.url, 'example.com?q=1');
    expect(g.method, 'GET');
  });

  test('urlencoded data becomes a table; unknown flags warn', () {
    final r = parseCurl(
      "curl -H 'Content-Type: application/x-www-form-urlencoded' "
      '-d a=1 -d b=2 --weird example.com',
    );
    expect((r.item.body as UrlEncodedBody).fields.map((f) => f.key), [
      'a',
      'b',
    ]);
    expect(r.warnings, isNotEmpty);
  });

  test('errors on non-curl and missing URL', () {
    expect(() => parseCurl('wget x'), throwsFormatException);
    expect(() => parseCurl('curl -X GET'), throwsFormatException);
    expect(looksLikeCurl('  curl -s x'), isTrue);
    expect(looksLikeCurl('curling'), isFalse);
  });

  test('toCurl round trips through parseCurl', () {
    final item = HttpRequestItem(
      id: '',
      name: 'n',
      method: 'POST',
      url: "https://x.test/a?q=it's",
      headers: const [KeyValue(key: 'X-A', value: 'b')],
      body: const RawBody(RawBodyLanguage.json, '{"a":"it\'s"}'),
      auth: const BasicAuth(username: 'u', password: 'p'),
      settings: const RequestSettings(verifyTls: false),
    );
    final cmd = toCurl(item);
    final back = parseCurl(cmd).item;
    expect(back.method, 'POST');
    expect(back.url, item.url);
    expect((back.body as RawBody).text, '{"a":"it\'s"}');
    expect((back.auth as BasicAuth).password, 'p');
    expect(back.settings.verifyTls, false);
    expect(back.headers.any((h) => h.key == 'X-A'), isTrue);
  });

  test('toCurl can resolve variables', () {
    final cmd = toCurl(
      const HttpRequestItem(id: '', name: 'n', url: '{{h}}/x'),
      resolve: (s) => s.replaceAll('{{h}}', 'http://a.test'),
    );
    expect(cmd, contains("'http://a.test/x'"));
  });
}
