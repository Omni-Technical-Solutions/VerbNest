import 'dart:convert';

import 'package:verbnest_core/verbnest_core.dart';
import 'package:verbnest_import/verbnest_import.dart';
import 'package:verbnest_storage/verbnest_storage.dart';
import 'package:test/test.dart';

const sample =
    '''
{
  "info": {"name": "Shop", "_postman_id": "x", "schema": "$postmanSchema",
           "description": "demo"},
  "auth": {"type": "bearer", "bearer": [{"key": "token", "value": "{{tok}}"}]},
  "variable": [{"key": "base", "value": "https://shop.test"}],
  "item": [
    {"name": "Users", "item": [
      {"name": "Get user",
       "event": [{"listen": "prerequest", "script": {"exec": ["a();", "b();"]}},
                 {"listen": "test", "script": {"exec": ["pm.test(1);"]}}],
       "request": {
         "method": "GET",
         "header": [{"key": "X-A", "value": "1"},
                    {"key": "X-Off", "value": "2", "disabled": true}],
         "url": {"raw": "{{base}}/users/:id?x=1&y=2",
                 "host": ["{{base}}"], "path": ["users", ":id"],
                 "query": [{"key": "x", "value": "1"}, {"key": "y", "value": "2"},
                           {"key": "off", "value": "z", "disabled": true}],
                 "variable": [{"key": "id", "value": "42"}]},
         "auth": {"type": "noauth"}
       },
       "response": [{"name": "ok"}]},
      {"name": "Create",
       "request": {"method": "POST",
         "body": {"mode": "raw", "raw": "{}", "options": {"raw": {"language": "json"}}},
         "url": "{{base}}/users"}}
    ]},
    {"name": "Upload", "request": {"method": "POST",
       "body": {"mode": "formdata", "formdata": [
         {"key": "a", "value": "1", "type": "text"},
         {"key": "f", "src": "/tmp/f", "type": "file"}]},
       "url": {"raw": "{{base}}/up"}}},
    {"name": "Graph", "request": {"method": "POST",
       "body": {"mode": "protobuf", "protobuf": {"x": 1}},
       "url": "{{base}}/g"}},
    {"name": "Custom auth", "request": {"method": "GET",
       "auth": {"type": "hawk", "hawk": [{"key": "region", "value": "eu"}]},
       "url": "{{base}}/aws"}}
  ]
}
''';

void main() {
  oauthRoundTrip();
  final json = jsonDecode(sample);

  test('imports folders, auth, variables, scripts and bodies', () {
    final r = importPostmanCollection(json);
    final c = r.collection;
    expect(c.name, 'Shop');
    expect(c.description, 'demo');
    expect((c.auth as BearerAuth).token, '{{tok}}');
    expect(c.variables.single.key, 'base');
    expect(c.children, hasLength(4));

    final users = c.children.first as FolderNode;
    final get = (users.children.first as RequestNode).item;
    expect(get.url, '{{base}}/users/:id?x=1&y=2');
    expect(get.params.map((p) => '${p.key}:${p.enabled}'), [
      'x:true',
      'y:true',
      'off:false',
    ]);
    expect(get.pathVars.single.value, '42');
    expect(get.headers.last.enabled, isFalse);
    expect(get.auth, isA<NoAuth>());
    expect(get.scripts.pre, 'a();\nb();');
    expect(get.scripts.post, 'pm.test(1);');
    expect((c.children.first as FolderNode).children.first, isA<RequestNode>());
    expect(
      ((c.children.first as FolderNode).children.first as RequestNode).examples,
      isNotEmpty,
    );

    final upload = (c.children[1] as RequestNode).item;
    final fields = (upload.body as FormDataBody).fields;
    expect(fields[1].type, KeyValueType.file);
    expect(fields[1].value, '/tmp/f');

    final graph = (c.children[2] as RequestNode).item;
    expect(graph.extra['postman.body'], isNotNull);
    expect((c.children[3] as RequestNode).item.auth, isA<RawAuth>());
  });

  test('round trip through the workspace keeps content', () {
    final db = WorkspaceDatabase.memory();
    addTearDown(db.close);
    final repo = WorkspaceRepository(db);
    final id = saveImportedCollection(
      repo,
      importPostmanCollection(json).collection,
    );
    final exported = exportPostmanCollection(loadCollectionTree(repo, id));
    final again = importPostmanCollection(exported);

    String dump(FolderNode f) => jsonEncode(_flat(f));
    // The sample has no examples, so both passes match.
    final first = importPostmanCollection(json).collection;
    expect(dump(again.collection), dump(first));
    expect(exported['info'], containsPair('schema', postmanSchema));

    // Unsupported body and auth are written back unchanged.
    final items = exported['item'] as List;
    final graph = (items[2] as Map)['request'] as Map;
    expect((graph['body'] as Map)['mode'], 'protobuf');
    final aws = (items[3] as Map)['request'] as Map;
    expect((aws['auth'] as Map)['type'], 'hawk');
  });

  test('not a collection throws', () {
    expect(() => importPostmanCollection({'a': 1}), throwsFormatException);
  });

  test('environments import and export', () {
    final env = importPostmanEnvironment({
      'name': 'Dev',
      'values': [
        {'key': 'a', 'value': '1', 'enabled': true},
        {'key': 's', 'value': 'sec', 'type': 'secret'},
        {'key': 'off', 'value': 'x', 'enabled': false},
      ],
    });
    expect(env.name, 'Dev');
    expect(env.variables[1].secret, isTrue);
    expect(env.variables[2].enabled, isFalse);
    final out = exportPostmanEnvironment(env.name, env.variables);
    expect(((out['values'] as List)[1] as Map)['value'], '');
    final withSecrets = exportPostmanEnvironment(
      env.name,
      env.variables,
      includeSecrets: true,
    );
    expect(((withSecrets['values'] as List)[1] as Map)['value'], 'sec');
    expect(looksLikePostmanEnvironment(json), isFalse);
  });
}

Object? _flat(ImportNode n) => switch (n) {
  FolderNode() => {
    'n': n.name,
    'd': n.description,
    'a': n.auth.toJson(),
    'v': [for (final v in n.variables) '${v.key}=${v.value}'],
    'c': [for (final c in n.children) _flat(c)],
  },
  RequestNode() => {
    'n': n.item.name,
    'm': n.item.method,
    'u': n.item.url,
    'p': n.item.params.map((p) => p.toJson()).toList(),
    'pv': n.item.pathVars.map((p) => p.toJson()).toList(),
    'h': n.item.headers.map((p) => p.toJson()).toList(),
    'b': n.item.body.toJson(),
    'a': n.item.auth.toJson(),
    's': n.item.scripts.toJson(),
    'x': n.item.extra,
  },
};

void oauthRoundTrip() {
  test('oauth2 auth survives a Postman round trip', () {
    const auth = OAuth2Auth(
      grant: OAuth2Grant.password,
      tokenUrl: 'https://t/token',
      clientId: 'id',
      clientSecret: 's',
      scope: 'x',
      username: 'u',
      password: 'p',
      clientAuthInBody: true,
    );
    final doc = exportPostmanCollection(
      FolderNode(
        'C',
        auth: auth,
        children: [
          RequestNode(
            const HttpRequestItem(id: '', name: 'r', url: 'http://h.test'),
          ),
        ],
      ),
    );
    final back = importPostmanCollection(jsonDecode(jsonEncode(doc)));
    expect(back.collection.auth.toJson(), auth.toJson());
  });

  test('digest, aws, jwt and pkce auth survive a Postman round trip', () {
    for (final a in <Auth>[
      const DigestAuth(username: 'u', password: 'p'),
      const AwsV4Auth(
        accessKey: 'a',
        secretKey: 'k',
        region: 'r',
        service: 's',
      ),
      const JwtAuth(secret: 's', payload: '{"x":1}'),
      const OAuth2Auth(
        grant: OAuth2Grant.authorizationCode,
        authUrl: 'https://a',
        tokenUrl: 'https://t',
        clientId: 'c',
      ),
      const OAuth2Auth(
        grant: OAuth2Grant.authorizationCode,
        usePkce: false,
        authUrl: 'https://a',
        tokenUrl: 'https://t',
      ),
      const OAuth2Auth(grant: OAuth2Grant.implicit, authUrl: 'https://a'),
    ]) {
      final doc = exportPostmanCollection(FolderNode('C', auth: a));
      final back = importPostmanCollection(jsonDecode(jsonEncode(doc)));
      expect(back.collection.auth.toJson(), a.toJson());
    }
  });

  test('saved responses become examples and survive export', () {
    final doc = {
      'info': {'name': 'C', 'schema': postmanSchema},
      'item': [
        {
          'name': 'r',
          'request': {'method': 'GET', 'url': 'http://h.test/a'},
          'response': [
            {
              'name': 'ok',
              'code': 200,
              'status': 'OK',
              'header': [
                {'key': 'X-A', 'value': '1'},
              ],
              'body': '{"a":1}',
              'originalRequest': {'method': 'GET', 'url': 'http://h.test/a'},
            },
          ],
        },
      ],
    };
    final imp = importPostmanCollection(doc);
    expect(imp.warnings, isEmpty);
    final db = WorkspaceDatabase.memory();
    addTearDown(db.close);
    final repo = WorkspaceRepository(db);
    final id = saveImportedCollection(repo, imp.collection);
    final req = repo.children(id).single.id;
    final ex = repo.examples(req).single;
    expect(ex.name, 'ok');
    expect(ex.data['status'], 200);
    expect(utf8.decode(ex.body), '{"a":1}');

    final out = exportPostmanCollection(loadCollectionTree(repo, id));
    final resp =
        (((out['item'] as List).single as Map)['response'] as List).single
            as Map;
    expect(resp['code'], 200);
    expect(resp['body'], '{"a":1}');
    expect((resp['header'] as List).single, {'key': 'X-A', 'value': '1'});
  });
}
