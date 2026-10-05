import 'dart:convert';

import 'package:postit_core/postit_core.dart';
import 'package:postit_import/postit_import.dart';
import 'package:test/test.dart';

const item = HttpRequestItem(
  id: 'r',
  name: 'Users',
  method: 'POST',
  url: 'https://api.test/graphql',
  body: GraphqlBody(
    query: 'query U(\$n: Int) { users(first: \$n) { name } }',
    variables: '{"n": {{count}}}',
    operationName: 'U',
  ),
);

String resolve(String s) => s.replaceAll('{{count}}', '5');

void main() {
  group('Postman', () {
    final collection = {
      'info': {'name': 'G', 'schema': postmanSchema},
      'item': [
        {
          'name': 'q',
          'request': {
            'method': 'POST',
            'url': 'https://api.test/graphql',
            'body': {
              'mode': 'graphql',
              'graphql': {'query': '{ me { id } }', 'variables': '{"a":1}'},
            },
          },
        },
        {
          'name': 'object variables',
          'request': {
            'method': 'POST',
            'url': 'https://api.test/graphql',
            'body': {
              'mode': 'graphql',
              'graphql': {
                'query': '{ a }',
                'variables': {'x': 1},
              },
            },
          },
        },
      ],
    };

    test('graphql bodies import as GraphqlBody', () {
      final r = importPostmanCollection(collection);
      final first = (r.collection.children[0] as RequestNode).item.body;
      expect(first, isA<GraphqlBody>());
      expect((first as GraphqlBody).query, '{ me { id } }');
      expect(first.variables, '{"a":1}');
      final second = (r.collection.children[1] as RequestNode).item.body;
      expect((second as GraphqlBody).variables, '{"x":1}');
      expect(r.warnings, isEmpty);
    });

    test('export writes the same graphql mode back', () {
      final imported = importPostmanCollection(collection).collection;
      final exported = exportPostmanCollection(imported);
      final body =
          ((exported['item'] as List).first as Map)['request']['body'] as Map;
      expect(body['mode'], 'graphql');
      expect(body['graphql'], {
        'query': '{ me { id } }',
        'variables': '{"a":1}',
      });
      final again = importPostmanCollection(exported).collection;
      expect(
        ((again.children[0] as RequestNode).item.body as GraphqlBody).query,
        '{ me { id } }',
      );
    });
  });

  group('cURL and code generation', () {
    test('cURL sends the JSON payload with a content type', () {
      final text = toCurl(item, resolve: resolve);
      expect(text, contains('Content-Type: application/json'));
      final data = RegExp(r"--data-raw '(.*)'").firstMatch(text)!.group(1)!;
      final payload = jsonDecode(data) as Map;
      expect(payload['variables'], {'n': 5});
      expect(payload['operationName'], 'U');
      expect(payload['query'], contains('users(first: \$n)'));
    });

    test('unresolved variables still export without failing', () {
      final bad = item.copyWith(
        body: const GraphqlBody(query: '{ a }', variables: '{"n": {{count}}}'),
      );
      final text = toCurl(bad);
      expect(text, contains('--data-raw'));
      expect(text, isNot(contains('variables')));
    });

    test('other languages carry the payload as a text body', () {
      for (final lang in [
        CodeLanguage.javascriptFetch,
        CodeLanguage.pythonRequests,
        CodeLanguage.dartHttp,
      ]) {
        final code = generateCode(lang, item, resolve: resolve);
        expect(code, contains('users(first: '), reason: lang.label);
        expect(code, contains('application/json'), reason: lang.label);
      }
    });
  });

  test('copyWith keeps untouched fields', () {
    final b = (item.body as GraphqlBody).copyWith(operationName: 'X');
    expect(b.operationName, 'X');
    expect(b.query, (item.body as GraphqlBody).query);
  });

  test('GET exports carry the operation in the URL', () {
    final get = item.copyWith(method: 'GET');
    final curl = toCurl(get, resolve: resolve);
    expect(curl, contains('graphql?query='));
    expect(curl, contains('operationName=U'));
    expect(curl, isNot(contains('--data-raw')));
    final code = generateCode(
      CodeLanguage.pythonRequests,
      get,
      resolve: resolve,
    );
    expect(code, contains('graphql?query='));
    expect(code, isNot(contains('data=')));
  });
}
