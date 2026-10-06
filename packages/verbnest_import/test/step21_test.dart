import 'dart:convert';

import 'package:verbnest_core/verbnest_core.dart';
import 'package:verbnest_import/verbnest_import.dart';
import 'package:test/test.dart';

const petstoreYaml = '''
openapi: 3.0.3
info:
  title: Pet API
  description: Pets
servers:
  - url: https://{env}.pets.test/v1/
    variables:
      env:
        default: api
tags:
  - name: pets
    description: Pet operations
security:
  - bearerAuth: []
paths:
  /pets:
    parameters:
      - name: X-Trace
        in: header
        schema: {type: string}
    get:
      tags: [pets]
      summary: List pets
      parameters:
        - name: limit
          in: query
          required: true
          schema: {type: integer, default: 20}
        - name: tag
          in: query
          schema: {type: string, example: cat}
    post:
      tags: [pets]
      operationId: addPet
      requestBody:
        content:
          application/json:
            schema:
              \$ref: '#/components/schemas/Pet'
  /pets/{petId}:
    get:
      summary: One pet
      parameters:
        - name: petId
          in: path
          required: true
          schema: {type: integer, example: 7}
  /login:
    post:
      tags: [auth]
      requestBody:
        content:
          application/x-www-form-urlencoded:
            schema:
              type: object
              properties:
                user: {type: string}
                pass: {type: string}
components:
  securitySchemes:
    bearerAuth: {type: http, scheme: bearer}
  schemas:
    Pet:
      allOf:
        - \$ref: '#/components/schemas/Base'
        - type: object
          properties:
            name: {type: string, example: Rex}
            tags:
              type: array
              items: {type: string}
            parent:
              \$ref: '#/components/schemas/Pet'
    Base:
      type: object
      properties:
        id: {type: integer, format: int64}
        born: {type: string, format: date-time}
''';

RequestNode find(FolderNode f, String name) {
  for (final c in f.children) {
    if (c is RequestNode && c.item.name == name) return c;
    if (c is FolderNode) {
      final r = c.children.whereType<RequestNode>().where(
        (x) => x.item.name == name,
      );
      if (r.isNotEmpty) return r.first;
    }
  }
  throw StateError('no $name');
}

void main() {
  group('OpenAPI', () {
    final doc = decodeJsonOrYaml(petstoreYaml);
    test('is recognised, YAML or JSON', () {
      expect(looksLikeOpenApi(doc), isTrue);
      expect(looksLikeOpenApi(decodeJsonOrYaml('{"a":1}')), isFalse);
      expect(
        looksLikeOpenApi(decodeJsonOrYaml('{"swagger":"2.0","paths":{}}')),
        isTrue,
      );
      expect(decodeJsonOrYaml('{ not json'), isNull);
    });

    test('folders by tag, base URL variable and collection auth', () {
      final r = importOpenApi(doc);
      final c = r.collection;
      expect(c.name, 'Pet API');
      expect(c.variables.single.key, 'baseUrl');
      expect(c.variables.single.value, 'https://api.pets.test/v1');
      expect(c.auth, isA<BearerAuth>());
      final folders = c.children.whereType<FolderNode>().map((f) => f.name);
      expect(folders, containsAll(['pets', 'auth']));
      expect(
        c.children
            .whereType<FolderNode>()
            .firstWhere((f) => f.name == 'pets')
            .description,
        'Pet operations',
      );
      // An untagged operation sits at the top.
      expect(c.children.whereType<RequestNode>().single.item.name, 'One pet');
    });

    test('parameters: required query enabled, optional listed but off', () {
      final list = find(importOpenApi(doc).collection, 'List pets').item;
      expect(list.url, '{{baseUrl}}/pets?limit=20');
      expect(list.params.map((p) => (p.key, p.value, p.enabled)), [
        ('limit', '20', true),
        ('tag', 'cat', false),
      ]);
      // Path-level header parameter is inherited by the operation.
      expect(list.headers.single.key, 'X-Trace');
      expect(list.headers.single.enabled, isFalse);
    });

    test('path variables use :name with the example value', () {
      final one = find(importOpenApi(doc).collection, 'One pet').item;
      expect(one.url, '{{baseUrl}}/pets/:petId');
      expect(one.pathVars.single.key, 'petId');
      expect(one.pathVars.single.value, '7');
    });

    test('JSON body is built from the schema, with allOf and cycles', () {
      final add = find(importOpenApi(doc).collection, 'addPet').item;
      final body = add.body as RawBody;
      expect(body.language, RawBodyLanguage.json);
      final j = jsonDecode(body.text) as Map;
      expect(j['name'], 'Rex');
      expect(j['id'], 0);
      expect(j['born'], '2024-01-01T00:00:00Z');
      expect(j['tags'], ['string']);
      expect(j.containsKey('parent'), isTrue);
    });

    test('form bodies become urlencoded fields', () {
      final login = find(importOpenApi(doc).collection, 'POST /login').item;
      final body = login.body as UrlEncodedBody;
      expect(body.fields.map((f) => f.key), ['user', 'pass']);
    });

    test('Swagger 2.0: host, basePath, body and form parameters', () {
      final r = importOpenApi({
        'swagger': '2.0',
        'info': {'title': 'Old'},
        'host': 'old.test',
        'basePath': '/api/',
        'schemes': ['http', 'https'],
        'securityDefinitions': {
          'key': {'type': 'apiKey', 'in': 'header', 'name': 'X-Key'},
        },
        'security': [
          {'key': <String>[]},
        ],
        'paths': {
          '/things': {
            'post': {
              'consumes': ['application/json'],
              'parameters': [
                {
                  'name': 'b',
                  'in': 'body',
                  'schema': {
                    'type': 'object',
                    'properties': {
                      'n': {'type': 'integer', 'example': 3},
                    },
                  },
                },
              ],
            },
            'put': {
              'parameters': [
                {'name': 'f', 'in': 'formData', 'type': 'file'},
                {'name': 'label', 'in': 'formData', 'type': 'string'},
              ],
            },
          },
        },
      });
      expect(r.collection.variables.single.value, 'https://old.test/api');
      expect(r.collection.auth, isA<ApiKeyAuth>());
      final post = find(r.collection, 'POST /things').item;
      expect(jsonDecode((post.body as RawBody).text), {'n': 3});
      final put = find(r.collection, 'PUT /things').item;
      final form = put.body as FormDataBody;
      expect(form.fields.first.type, KeyValueType.file);
    });

    test('external references are reported, not followed', () {
      final r = importOpenApi({
        'openapi': '3.0.0',
        'paths': {
          '/x': {
            'get': {
              'parameters': [
                {r'$ref': 'other.yaml#/p'},
              ],
            },
          },
        },
      });
      expect(r.warnings.single, contains('External reference'));
    });

    test('an unsupported security scheme is reported', () {
      final r = importOpenApi({
        'openapi': '3.0.0',
        'security': [
          {'o': <String>[]},
        ],
        'components': {
          'securitySchemes': {
            'o': {'type': 'oauth2'},
          },
        },
        'paths': <String, Object?>{},
      });
      expect(r.collection.auth, isA<InheritAuth>());
      expect(r.warnings.single, contains('oauth2'));
    });
  });

  group('HAR', () {
    final har = {
      'log': {
        'creator': {'name': 'WebInspector'},
        'entries': [
          {
            'request': {
              'method': 'POST',
              'url': 'https://a.test/login?next=%2F',
              'headers': [
                {'name': ':authority', 'value': 'a.test'},
                {'name': 'Host', 'value': 'a.test'},
                {'name': 'Content-Type', 'value': 'application/json'},
                {'name': 'X-Id', 'value': '1'},
              ],
              'postData': {'mimeType': 'application/json', 'text': '{"a":1}'},
            },
          },
          {
            'request': {
              'method': 'POST',
              'url': 'https://a.test/f',
              'headers': <Object?>[],
              'postData': {
                'mimeType': 'application/x-www-form-urlencoded',
                'params': [
                  {'name': 'u', 'value': 'v'},
                ],
              },
            },
          },
        ],
      },
    };

    test('entries become requests', () {
      expect(looksLikeHar(har), isTrue);
      final r = importHar(har);
      expect(r.collection.name, 'HAR import (WebInspector)');
      final a = (r.collection.children.first as RequestNode).item;
      expect(a.name, 'POST a.test/login');
      expect(a.params.single.key, 'next');
      expect(a.headers.map((h) => h.key), ['X-Id']);
      expect((a.body as RawBody).text, '{"a":1}');
      final b = (r.collection.children.last as RequestNode).item;
      expect((b.body as UrlEncodedBody).fields.single.key, 'u');
    });

    test('rejects other JSON', () {
      expect(looksLikeHar({'log': {}}), isFalse);
      expect(() => importHar({}), throwsFormatException);
    });
  });

  group('code generation', () {
    final item = HttpRequestItem(
      id: 'r',
      name: 'n',
      method: 'POST',
      url: 'https://a.test/x?q=1',
      headers: const [
        KeyValue(key: 'X-A', value: "it's"),
        KeyValue(key: 'Off', value: 'no', enabled: false),
      ],
      body: const RawBody(RawBodyLanguage.json, '{"a":"\$x"}\n'),
    );

    test('fetch', () {
      final code = generateCode(CodeLanguage.javascriptFetch, item);
      expect(code, contains('await fetch("https://a.test/x?q=1"'));
      expect(code, contains('method: "POST"'));
      expect(code, contains('"X-A": "it\'s"'));
      expect(code, contains('"Content-Type": "application/json"'));
      expect(code, isNot(contains('Off')));
      expect(code, contains(r'body: "{\"a\":\"$x\"}\n"'));
    });

    test('python escapes quotes and sends basic auth', () {
      final code = generateCode(
        CodeLanguage.pythonRequests,
        item,
        auth: const BasicAuth(username: 'ann', password: 'pw'),
      );
      expect(code, contains("'X-A': 'it\\'s'"));
      expect(code, contains("auth=('ann', 'pw')"));
      expect(code, contains(r"data='{"));
    });

    test('dart escapes dollars and uses bearer', () {
      final code = generateCode(
        CodeLanguage.dartHttp,
        item,
        auth: const BearerAuth(token: 'tok'),
      );
      expect(code, contains(r'\$x'));
      expect(code, contains("'Authorization': 'Bearer tok'"));
      expect(code, contains("http.Request("));
    });

    test('forms, multipart, api key in query and variable resolving', () {
      final form = item.copyWith(
        body: const UrlEncodedBody([KeyValue(key: 'k', value: '{{v}}')]),
      );
      final code = generateCode(
        CodeLanguage.pythonRequests,
        form,
        resolve: (s) => s.replaceAll('{{v}}', 'resolved'),
        auth: const ApiKeyAuth(
          key: 'key',
          value: 's',
          addTo: ApiKeyLocation.query,
        ),
      );
      expect(code, contains("'k': 'resolved'"));
      expect(code, contains("x?q=1&key=s"));
      final multi = item.copyWith(
        body: const FormDataBody([
          KeyValue(key: 'f', value: '/tmp/a.png', type: KeyValueType.file),
          KeyValue(key: 't', value: 'x'),
        ]),
      );
      expect(
        generateCode(CodeLanguage.dartHttp, multi),
        contains("MultipartFile.fromPath('f', '/tmp/a.png')"),
      );
      expect(
        generateCode(CodeLanguage.javascriptFetch, multi),
        contains('form.append("t", "x")'),
      );
    });

    test('curl delegates to toCurl', () {
      expect(
        generateCode(CodeLanguage.curl, item),
        startsWith("curl -X POST 'https://a.test/x?q=1'"),
      );
    });
  });
}
