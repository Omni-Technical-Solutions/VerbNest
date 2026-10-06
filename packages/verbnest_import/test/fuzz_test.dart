import 'dart:convert';
import 'dart:math';

import 'package:verbnest_import/verbnest_import.dart';
import 'package:test/test.dart';

/// Importers read untrusted files. Any input may be rejected, but only with a
/// [FormatException]; anything else (a cast or range error) is a bug.
void _mustNotCrash(void Function() body) {
  try {
    body();
  } on FormatException {
    // Rejecting bad input is fine.
  }
}

Object? _mutate(Object? v, Random r, int depth) {
  switch (r.nextInt(8)) {
    case 0:
      return null;
    case 1:
      return r.nextInt(1000) - 500;
    case 2:
      return r.nextBool();
    case 3:
      return 'x' * r.nextInt(50);
    case 4:
      return <Object?>[];
    case 5:
      return <String, Object?>{};
  }
  if (v is Map && depth < 12) {
    return {
      for (final e in v.entries)
        if (r.nextInt(10) != 0) e.key: _mutate(e.value, r, depth + 1),
    };
  }
  if (v is List && depth < 12) {
    return [for (final e in v) _mutate(e, r, depth + 1)];
  }
  return v;
}

const _postman = {
  'info': {
    'name': 'c',
    'schema':
        'https://schema.getpostman.com/json/collection/v2.1.0/collection.json',
  },
  'auth': {
    'type': 'bearer',
    'bearer': [
      {'key': 'token', 'value': 't'},
    ],
  },
  'variable': [
    {'key': 'a', 'value': 'b'},
  ],
  'item': [
    {
      'name': 'folder',
      'item': [
        {
          'name': 'r',
          'request': {
            'method': 'POST',
            'header': [
              {'key': 'A', 'value': 'b'},
            ],
            'url': {
              'raw': 'https://x.test/a?b=c',
              'host': ['x', 'test'],
              'path': ['a'],
              'query': [
                {'key': 'b', 'value': 'c'},
              ],
            },
            'body': {'mode': 'raw', 'raw': '{}'},
          },
          'response': [
            {'name': 'ok', 'code': 200, 'body': '{}'},
          ],
        },
      ],
    },
  ],
};

const _openapi = {
  'openapi': '3.0.3',
  'info': {'title': 'T'},
  'servers': [
    {'url': 'https://a.test'},
  ],
  'paths': {
    '/p/{id}': {
      'get': {
        'tags': ['t'],
        'parameters': [
          {
            'name': 'id',
            'in': 'path',
            'required': true,
            'schema': {'type': 'string'},
          },
        ],
        'requestBody': {
          'content': {
            'application/json': {
              'schema': {
                'type': 'object',
                'properties': {
                  'n': {'type': 'integer'},
                },
              },
            },
          },
        },
      },
    },
  },
  'components': {
    'securitySchemes': {
      'b': {'type': 'http', 'scheme': 'bearer'},
    },
  },
};

const _har = {
  'log': {
    'entries': [
      {
        'request': {
          'method': 'GET',
          'url': 'https://a.test/x?y=1',
          'headers': [
            {'name': 'A', 'value': 'b'},
          ],
          'queryString': [
            {'name': 'y', 'value': '1'},
          ],
          'postData': {'mimeType': 'application/json', 'text': '{}'},
        },
      },
    ],
  },
};

void main() {
  test('mutated Postman, OpenAPI and HAR documents never crash', () {
    final r = Random(42);
    for (var i = 0; i < 1500; i++) {
      final postman = _mutate(_postman, r, 0);
      final openapi = _mutate(_openapi, r, 0);
      final har = _mutate(_har, r, 0);
      _mustNotCrash(() {
        if (looksLikePostmanCollection(postman)) {
          importPostmanCollection(postman);
        }
      });
      _mustNotCrash(() {
        if (looksLikePostmanEnvironment(postman)) {
          importPostmanEnvironment(postman);
        }
      });
      _mustNotCrash(() {
        if (looksLikeOpenApi(openapi)) importOpenApi(openapi);
      });
      _mustNotCrash(() {
        if (looksLikeHar(har)) importHar(har);
      });
    }
  });

  test('random and truncated cURL text never crashes', () {
    final r = Random(7);
    const base =
        r"""curl -X POST 'https://a.test/x' -H "A: b" -d '{"a":1}' -u u:p""";
    const alphabet = r'''curl -XHdu'"\$ ^`@=&?{}[]:/.%0123456789abc''';
    for (var i = 0; i < 2000; i++) {
      final cut = base.substring(0, r.nextInt(base.length + 1));
      final noise = String.fromCharCodes([
        for (var j = 0; j < r.nextInt(40); j++)
          alphabet.codeUnitAt(r.nextInt(alphabet.length)),
      ]);
      _mustNotCrash(() => parseCurl(cut));
      _mustNotCrash(() => parseCurl('curl $noise'));
    }
  });

  test('deeply nested JSON does not overflow the stack', () {
    final nested = jsonDecode('${'{"item":[' * 400}{}${']}' * 400}');
    _mustNotCrash(() {
      if (looksLikePostmanCollection(nested)) importPostmanCollection(nested);
    });
  });
}
