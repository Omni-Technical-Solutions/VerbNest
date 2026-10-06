import 'dart:convert';

import 'package:verbnest_core/verbnest_core.dart';
import 'package:verbnest_http/verbnest_http.dart';
import 'package:test/test.dart';
import 'package:test_server/test_server.dart';

HttpRequestItem item({
  String method = 'GET',
  String url = 'http://127.0.0.1/echo',
  List<KeyValue> headers = const [],
  List<KeyValue> pathVars = const [],
  RequestBody body = const NoBody(),
  Auth auth = const NoAuth(),
  RequestSettings settings = const RequestSettings(),
}) => HttpRequestItem(
  id: 'i',
  name: 'n',
  method: method,
  url: url,
  headers: headers,
  pathVars: pathVars,
  body: body,
  auth: auth,
  settings: settings,
);

VariableResolver vars(List<Variable> env) =>
    VariableResolver(VariableScopes(environment: env));

Future<PreparedRequest> build(
  HttpRequestItem i, {
  List<Variable> env = const [],
  RequestBuilder? builder,
  Auth? auth,
}) => (builder ?? RequestBuilder()).build(i, vars(env), auth: auth);

Map<String, String> headerMap(PreparedRequest p) => {
  for (final (k, v) in p.spec.headers) k.toLowerCase(): v,
};

void main() {
  graphqlGetTests();
  settingsMergeTests();
  group('url', () {
    test('substitutes variables and path variables', () async {
      final p = await build(
        item(
          url: '{{base}}/pets/:id/tags/:tag?x={{v}}',
          pathVars: const [
            KeyValue(key: 'id', value: '{{petId}}'),
            KeyValue(key: 'tag', value: 'a b', enabled: false),
          ],
        ),
        env: const [
          Variable(key: 'base', value: 'https://api.test'),
          Variable(key: 'petId', value: '42'),
          Variable(key: 'v', value: '1'),
        ],
      );
      expect(p.spec.url.toString(), 'https://api.test/pets/42/tags/:tag?x=1');
      expect(p.unresolved, isEmpty);
    });

    test('adds http:// when the scheme is missing', () async {
      final p = await build(item(url: 'localhost:3000/x'));
      expect(p.spec.url.scheme, 'http');
      expect(p.spec.url.port, 3000);
    });

    test('empty and invalid URLs are build errors', () async {
      expect(build(item(url: '  ')), throwsA(isA<RequestBuildError>()));
      expect(build(item(url: 'http://')), throwsA(isA<RequestBuildError>()));
    });

    test('reports unresolved variables and leaves them verbatim', () async {
      final p = await build(item(url: 'http://h/{{missing}}'));
      expect(p.unresolved, {'missing'});
    });

    test('method is resolved and upper-cased', () async {
      final p = await build(
        item(method: '{{m}}'),
        env: const [Variable(key: 'm', value: 'purge')],
      );
      expect(p.spec.method, 'PURGE');
    });
  });

  group('headers', () {
    test('only enabled, non-empty headers are sent; order kept', () async {
      final p = await build(
        item(
          headers: const [
            KeyValue(key: 'B', value: '2'),
            KeyValue(key: 'Off', value: 'x', enabled: false),
            KeyValue(key: '  ', value: 'blank'),
            KeyValue(key: 'A', value: '{{v}}'),
          ],
        ),
        env: const [Variable(key: 'v', value: '1')],
      );
      expect(p.spec.headers, [('B', '2'), ('A', '1')]);
    });
  });

  group('auth', () {
    test('bearer, basic and api key', () async {
      var p = await build(
        item(auth: const BearerAuth(token: '{{t}}')),
        env: const [Variable(key: 't', value: 'tok')],
      );
      expect(headerMap(p)['authorization'], 'Bearer tok');

      p = await build(
        item(
          auth: const BasicAuth(username: 'u', password: 'p'),
        ),
      );
      expect(
        headerMap(p)['authorization'],
        'Basic ${base64Encode(utf8.encode('u:p'))}',
      );

      p = await build(
        item(
          auth: const ApiKeyAuth(key: 'X-Key', value: 'k'),
        ),
      );
      expect(headerMap(p)['x-key'], 'k');
    });

    test('api key in the query is encoded and appended', () async {
      final p = await build(
        item(
          url: 'http://h/p?a=1',
          auth: const ApiKeyAuth(
            key: 'k',
            value: 'a b&c',
            addTo: ApiKeyLocation.query,
          ),
        ),
      );
      expect(p.spec.url.query, 'a=1&k=a+b%26c');
    });

    test('an explicit Authorization header beats generated auth', () async {
      final p = await build(
        item(
          headers: const [KeyValue(key: 'authorization', value: 'Custom x')],
          auth: const BearerAuth(token: 't'),
        ),
      );
      expect(
        p.spec.headers.where((h) => h.$1.toLowerCase() == 'authorization'),
        hasLength(1),
      );
      expect(headerMap(p)['authorization'], 'Custom x');
    });

    test('inherited auth is passed in by the caller', () async {
      final p = await build(
        item(auth: const InheritAuth()),
        auth: effectiveAuth(const InheritAuth(), [
          const BearerAuth(token: 'T'),
        ]),
      );
      expect(headerMap(p)['authorization'], 'Bearer T');
    });

    test('unsupported auth warns instead of failing', () async {
      final p = await build(item(auth: const RawAuth({'type': 'oauth2'})));
      expect(p.warnings.single, contains('oauth2'));
      expect(headerMap(p), isNot(contains('authorization')));
    });
  });

  group('bodies', () {
    test('raw sets Content-Type unless the user did', () async {
      var p = await build(
        item(
          method: 'POST',
          body: const RawBody(RawBodyLanguage.json, '{"a":"{{v}}"}'),
        ),
        env: const [Variable(key: 'v', value: 'é')],
      );
      expect(headerMap(p)['content-type'], 'application/json');
      expect(utf8.decode(p.spec.body!), '{"a":"é"}');

      p = await build(
        item(
          method: 'POST',
          headers: const [
            KeyValue(key: 'content-type', value: 'application/vnd.x+json'),
          ],
          body: const RawBody(RawBodyLanguage.json, '{}'),
        ),
      );
      expect(headerMap(p)['content-type'], 'application/vnd.x+json');
    });

    test('urlencoded', () async {
      final p = await build(
        item(
          method: 'POST',
          body: const UrlEncodedBody([
            KeyValue(key: 'a b', value: 'c&d'),
            KeyValue(key: 'off', value: 'x', enabled: false),
          ]),
        ),
      );
      expect(utf8.decode(p.spec.body!), 'a+b=c%26d');
      expect(headerMap(p)['content-type'], 'application/x-www-form-urlencoded');
    });

    test('multipart with a text and a file part', () async {
      final builder = RequestBuilder(
        readFile: (ref) async => utf8.encode('FILEDATA:$ref'),
      );
      final p = await build(
        item(
          method: 'POST',
          body: const FormDataBody([
            KeyValue(key: 'note', value: 'hi'),
            KeyValue(key: 'doc', value: '/tmp/a.txt', type: KeyValueType.file),
          ]),
        ),
        builder: builder,
      );
      final ct = headerMap(p)['content-type']!;
      final boundary = ct.split('boundary=').last;
      final text = utf8.decode(p.spec.body!);
      expect(text, startsWith('--$boundary\r\n'));
      expect(text, contains('name="note"\r\n\r\nhi\r\n'));
      expect(text, contains('name="doc"; filename="a.txt"'));
      expect(text, contains('FILEDATA:/tmp/a.txt'));
      expect(text, endsWith('--$boundary--\r\n'));
    });

    test('missing file access is a build error', () async {
      expect(
        build(
          item(
            method: 'POST',
            body: const FormDataBody([
              KeyValue(key: 'f', value: 'x', type: KeyValueType.file),
            ]),
          ),
        ),
        throwsA(isA<RequestBuildError>()),
      );
    });

    test('binary body uses the attachment bytes', () async {
      final builder = RequestBuilder(readFile: (ref) async => [1, 2, 3]);
      final p = await build(
        item(method: 'POST', body: const BinaryBody('att')),
        builder: builder,
      );
      expect(p.spec.body, [1, 2, 3]);
      expect(headerMap(p)['content-type'], 'application/octet-stream');
    });
  });

  group('settings', () {
    test('request overrides win over workspace defaults', () async {
      final builder = RequestBuilder(
        defaults: const HttpSettings(
          timeout: Duration(seconds: 9),
          verifyTls: true,
        ),
      );
      var p = await build(item(), builder: builder);
      expect(p.spec.settings.timeout, const Duration(seconds: 9));
      p = await build(
        item(
          settings: const RequestSettings(
            timeoutMs: 100,
            verifyTls: false,
            followRedirects: false,
          ),
        ),
        builder: builder,
      );
      expect(p.spec.settings.timeout, const Duration(milliseconds: 100));
      expect(p.spec.settings.verifyTls, isFalse);
      expect(p.spec.settings.followRedirects, isFalse);
    });
  });

  group('secrets', () {
    const env = [
      Variable(key: 'token', value: 'S3CRET-TOKEN', secret: true),
      Variable(key: 'pw', value: 'hunter2', secret: true),
    ];

    test('are tracked and masked in head and body', () async {
      final p = await build(
        item(
          method: 'POST',
          url: 'http://h/p?t={{token}}',
          auth: const BasicAuth(username: 'u', password: '{{pw}}'),
          body: const RawBody(RawBodyLanguage.text, 'pw={{pw}}'),
        ),
        env: env,
      );
      expect(p.secretNames, {'token', 'pw'});
      final head =
          'POST /p?t=S3CRET-TOKEN HTTP/1.1\r\nAuthorization: ${headerMap(p)['authorization']}\r\nX: hunter2\r\n';
      final masked = p.masker.maskHead(head);
      expect(masked, isNot(contains('S3CRET-TOKEN')));
      expect(masked, isNot(contains('hunter2')));
      expect(masked, contains('Authorization: ••••••'));
      expect(p.masker.maskText(utf8.decode(p.spec.body!)), 'pw=••••••');
    });

    test('custom api key header name is masked', () async {
      final p = await build(
        item(
          auth: const ApiKeyAuth(key: 'X-Api', value: 'plain'),
        ),
      );
      expect(
        p.masker.maskHead('GET / HTTP/1.1\r\nX-Api: plain\r\nHost: h\r\n'),
        'GET / HTTP/1.1\r\nX-Api: ••••••\r\nHost: h\r\n',
      );
    });
  });

  group('end to end against the test server', () {
    late TestServer server;
    final engine = HttpEngine();
    setUp(() async => server = await TestServer.start());
    tearDown(() => server.close());

    test('built request arrives as intended', () async {
      final p = await build(
        item(
          method: 'POST',
          url: '{{base}}/echo?x=1',
          headers: const [KeyValue(key: 'X-Mixed-Case', value: 'v')],
          auth: const BearerAuth(token: '{{t}}'),
          body: const RawBody(RawBodyLanguage.json, '{"ok":true}'),
        ),
        env: [
          Variable(key: 'base', value: server.baseUrl),
          const Variable(key: 't', value: 'abc', secret: true),
        ],
      );
      final r = await engine.send(p.spec);
      final echo = jsonDecode(r.bodyText) as Map<String, dynamic>;
      final names = (echo['headers'] as List).map((h) => h[0]).toList();
      expect(names.first, 'X-Mixed-Case');
      expect(names, containsAll(['Authorization', 'Content-Type']));
      expect(
        utf8.decode(base64Decode(echo['bodyBase64'] as String)),
        '{"ok":true}',
      );
      expect(p.masker.maskHead(r.sent.head), isNot(contains('abc')));
    });
  });
}

void settingsMergeTests() {
  test(
    'per-request redirect and decompress options override defaults',
    () async {
      final p = await RequestBuilder().build(
        const HttpRequestItem(
          id: '',
          name: 'n',
          url: 'http://h.test',
          settings: RequestSettings(
            maxRedirects: 2,
            keepMethodOnRedirect: true,
            stripAuthCrossOrigin: false,
            autoDecompress: false,
          ),
        ),
        VariableResolver(VariableScopes()),
      );
      final s = p.spec.settings;
      expect(s.maxRedirects, 2);
      expect(s.keepMethodOnRedirect, isTrue);
      expect(s.stripAuthCrossOrigin, isFalse);
      expect(s.autoDecompress, isFalse);
      final d = (await RequestBuilder().build(
        const HttpRequestItem(id: '', name: 'n', url: 'http://h.test'),
        VariableResolver(VariableScopes()),
      )).spec.settings;
      expect(d.stripAuthCrossOrigin, isTrue);
    },
  );

  test('RequestSettings copyWith can reset a field and round-trips', () {
    const s = RequestSettings(timeoutMs: 5, autoDecompress: false);
    expect(s.copyWith(timeoutMs: null).timeoutMs, isNull);
    expect(s.copyWith(verifyTls: false).timeoutMs, 5);
    final back = RequestSettings.fromJson(s.toJson());
    expect(back.autoDecompress, false);
    expect(back.keepMethodOnRedirect, isNull);
  });
}

void graphqlGetTests() {
  group('GraphQL over GET', () {
    const gql = GraphqlBody(
      query: 'query U(\$n: Int) { users(first: \$n) { name } }',
      variables: '{"n": {{count}}}',
      operationName: 'U',
    );

    test(
      'a GET puts the operation in the query string, with no body',
      () async {
        final p = await build(
          item(method: 'GET', url: 'http://h.test/graphql?x=1#f', body: gql),
          env: [const Variable(key: 'count', value: '5')],
        );
        expect(p.spec.body, isNull);
        expect(headerMap(p).containsKey('content-type'), isFalse);
        final q = p.spec.url.queryParameters;
        expect(q['x'], '1');
        expect(q['query'], contains('users(first: \$n)'));
        expect(jsonDecode(q['variables']!), {'n': 5});
        expect(q['operationName'], 'U');
        expect(p.spec.url.fragment, 'f');
      },
    );

    test('a POST still sends the JSON body', () async {
      final p = await build(
        item(method: 'POST', url: 'http://h.test/graphql', body: gql),
        env: [const Variable(key: 'count', value: '5')],
      );
      expect(p.spec.url.hasQuery, isFalse);
      expect(jsonDecode(utf8.decode(p.spec.body!))['operationName'], 'U');
    });

    test('bad variables fail the build with a clear message', () {
      expect(
        build(item(method: 'GET', url: 'http://h.test/graphql', body: gql)),
        throwsA(isA<RequestBuildError>()),
      );
    });
  });
}
