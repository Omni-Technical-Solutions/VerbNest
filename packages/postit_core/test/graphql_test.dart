import 'dart:convert';

import 'package:postit_core/postit_core.dart';
import 'package:test/test.dart';

const sdl = '''
"""The API"""
schema { query: RootQuery mutation: RootMutation }

scalar DateTime

"A user"
type User implements Node & Named {
  id: ID!
  "Display name"
  name(format: NameFormat = SHORT): String!
  friends(first: Int = 10, after: String): [User!]!
  createdAt: DateTime @deprecated(reason: "use created")
  role: Role
}

interface Node { id: ID! }
interface Named { name: String! }

enum Role { ADMIN USER @deprecated }
enum NameFormat { SHORT LONG }

input NewUser {
  name: String!
  tags: [String!] = ["a"]
}

union SearchResult = User | Post

type Post { id: ID! title: String }

directive @auth(role: Role) repeatable on FIELD_DEFINITION | OBJECT

type RootQuery {
  me: User
  user(id: ID!): User
  search(text: String!): [SearchResult!]!
}

type RootMutation { createUser(input: NewUser!): User }

extend type Post { author: User }
''';

Map<String, Object?> ref(String kind, [String? name, Object? of]) => {
  'kind': kind,
  'name': name,
  'ofType': of,
};

Map<String, Object?> introspection() => {
  'data': {
    '__schema': {
      'queryType': {'name': 'Query'},
      'mutationType': null,
      'subscriptionType': null,
      'types': [
        {
          'kind': 'OBJECT',
          'name': 'Query',
          'description': 'Root',
          'fields': [
            {
              'name': 'users',
              'description': 'All users',
              'isDeprecated': false,
              'args': [
                {
                  'name': 'first',
                  'type': ref('SCALAR', 'Int'),
                  'defaultValue': '10',
                },
              ],
              'type': ref(
                'NON_NULL',
                null,
                ref('LIST', null, ref('NON_NULL', null, ref('OBJECT', 'User'))),
              ),
            },
            {
              'name': 'old',
              'args': <Object?>[],
              'isDeprecated': true,
              'deprecationReason': 'gone',
              'type': ref('SCALAR', 'String'),
            },
          ],
          'interfaces': <Object?>[],
        },
        {
          'kind': 'OBJECT',
          'name': 'User',
          'fields': [
            {
              'name': 'id',
              'args': <Object?>[],
              'isDeprecated': false,
              'type': ref('NON_NULL', null, ref('SCALAR', 'ID')),
            },
            {
              'name': 'email',
              'args': <Object?>[],
              'isDeprecated': false,
              'type': ref('SCALAR', 'String'),
            },
          ],
          'interfaces': <Object?>[],
        },
        {'kind': 'SCALAR', 'name': 'String'},
        {'kind': 'SCALAR', 'name': 'Int'},
        {'kind': 'SCALAR', 'name': 'ID'},
        {'kind': 'OBJECT', 'name': '__Schema', 'fields': <Object?>[]},
      ],
    },
  },
};

void main() {
  group('payload', () {
    test('builds the JSON body', () {
      final j = jsonDecode(
        graphqlPayload(
          query: '{ me { id } }',
          variables: '{"a": 1}',
          operationName: ' Op ',
        ),
      );
      expect(j, {
        'query': '{ me { id } }',
        'variables': {'a': 1},
        'operationName': 'Op',
      });
    });

    test('empty variables and name are left out', () {
      final j = jsonDecode(graphqlPayload(query: '{a}', variables: '  '));
      expect(j, {'query': '{a}'});
    });

    test('bad variables are explained', () {
      expect(
        () => graphqlPayload(query: '{a}', variables: '{oops'),
        throwsA(
          isA<FormatException>().having(
            (e) => e.message,
            'message',
            contains('not valid JSON'),
          ),
        ),
      );
      expect(
        () => graphqlPayload(query: '{a}', variables: '[1]'),
        throwsA(
          isA<FormatException>().having(
            (e) => e.message,
            'message',
            contains('object'),
          ),
        ),
      );
    });

    test('finds operation names, skipping strings, comments and bodies', () {
      const doc = '''
# query Commented { a }
query First(\$id: ID!) { user(id: \$id) { name(format: "query Fake") } }
mutation Second { x }
{ anonymous }
subscription { y }
''';
      expect(graphqlOperationNames(doc), ['First', 'Second']);
    });
  });

  group('body model', () {
    test('round trips through JSON', () {
      const b = GraphqlBody(
        query: '{ a }',
        variables: '{"x":1}',
        operationName: 'A',
      );
      final back = RequestBody.fromJson(b.toJson());
      expect(back, isA<GraphqlBody>());
      expect((back as GraphqlBody).query, '{ a }');
      expect(back.variables, '{"x":1}');
      expect(back.operationName, 'A');
      expect(back.defaultContentType, 'application/json');
    });

    test('empty fields are not stored', () {
      expect(const GraphqlBody().toJson(), {'mode': 'graphql', 'graphql': {}});
    });
  });

  group('introspection', () {
    final schema = GraphqlSchema.fromIntrospection(introspection());

    test('reads types, fields and wrapped types', () {
      expect(schema.queryType, 'Query');
      expect(schema.mutationType, isNull);
      final users = schema.type('Query')!.fields.first;
      expect(users.type, '[User!]!');
      expect(users.namedType, 'User');
      expect(users.args.single.defaultValue, '10');
      expect(schema.type('Query')!.fields.last.deprecated, 'gone');
    });

    test('hides built-ins and __ types', () {
      expect(schema.userTypes.map((t) => t.name), ['Query', 'User']);
    });

    test('accepts the result without the data wrapper', () {
      final inner = (introspection()['data'] as Map<String, Object?>);
      expect(GraphqlSchema.fromIntrospection(inner).queryType, 'Query');
    });

    test('server errors and other JSON are rejected', () {
      expect(
        () => GraphqlSchema.fromIntrospection({
          'errors': [
            {'message': 'introspection is disabled'},
          ],
        }),
        throwsA(
          isA<FormatException>().having(
            (e) => e.message,
            'message',
            contains('introspection is disabled'),
          ),
        ),
      );
      expect(
        () => GraphqlSchema.fromIntrospection({'hello': 1}),
        throwsFormatException,
      );
    });
  });

  group('SDL', () {
    final schema = GraphqlSchema.fromSdl(sdl);

    test('reads definitions', () {
      expect(schema.queryType, 'RootQuery');
      expect(schema.mutationType, 'RootMutation');
      final user = schema.type('User')!;
      expect(user.kind, GqlKind.object);
      expect(user.description, 'A user');
      expect(user.interfaces, ['Node', 'Named']);
      expect(user.fields.map((f) => f.name), [
        'id',
        'name',
        'friends',
        'createdAt',
        'role',
      ]);
      final name = user.fields[1];
      expect(name.description, 'Display name');
      expect(name.args.single.defaultValue, 'SHORT');
      expect(user.fields[2].type, '[User!]!');
      expect(user.fields[3].deprecated, 'use created');
      expect(schema.type('Role')!.enumValues.last.deprecated, '');
      expect(schema.type('NewUser')!.inputFields.last.defaultValue, '["a"]');
      expect(schema.type('SearchResult')!.possibleTypes, ['User', 'Post']);
    });

    test('extend merges into the existing type', () {
      expect(schema.type('Post')!.fields.map((f) => f.name), [
        'id',
        'title',
        'author',
      ]);
    });

    test('directive definitions are skipped', () {
      expect(schema.type('RootQuery')!.fields, hasLength(3));
    });

    test('SDL to text to SDL keeps the schema', () {
      final again = GraphqlSchema.fromSdl(schema.toSdl());
      expect(again.toSdl(), schema.toSdl());
      expect(again.queryType, 'RootQuery');
      expect(again.type('User')!.fields[3].deprecated, 'use created');
    });

    test('introspection to SDL to schema keeps the types', () {
      final fromIntro = GraphqlSchema.fromIntrospection(introspection());
      final back = GraphqlSchema.fromSdl(fromIntro.toSdl());
      expect(back.userTypes.map((t) => t.name), ['Query', 'User']);
      expect(back.type('Query')!.fields.first.type, '[User!]!');
      expect(back.type('Query')!.fields.last.deprecated, 'gone');
    });

    test('errors name the line', () {
      expect(
        () => GraphqlSchema.fromSdl('type A {\n  x String\n}'),
        throwsA(
          isA<FormatException>().having(
            (e) => e.message,
            'message',
            contains('line'),
          ),
        ),
      );
      expect(() => GraphqlSchema.fromSdl(''), throwsFormatException);
      expect(() => GraphqlSchema.fromSdl('query { a }'), throwsFormatException);
    });
  });

  group('completion', () {
    final schema = GraphqlSchema.fromSdl(sdl);

    List<String> at(String text, {String marker = '|'}) {
      final offset = text.indexOf(marker);
      final c = graphqlComplete(schema, text.replaceFirst(marker, ''), offset);
      return c?.items.map((i) => i.label).toList() ?? const [];
    }

    test('root fields of the query type', () {
      expect(at('{ | }'), containsAll(['me', 'user', 'search', '__typename']));
    });

    test('filters by the typed prefix', () {
      expect(at('{ us| }'), ['user']);
    });

    test('nested selection follows field types', () {
      expect(at('{ me { | } }'), contains('friends'));
      expect(at('{ me { friends { na| } } }'), ['name']);
    });

    test('mutation and named operations', () {
      expect(at('mutation Add { | }'), ['createUser', '__typename']);
      expect(at('query Q(\$a: ID) { user(id: \$a) { | } }'), contains('role'));
    });

    test('inline fragments and unions', () {
      expect(
        at('{ search(text: "x") { ... on Post { | } } }'),
        contains('title'),
      );
      expect(
        at('{ search(text: "x") { | } }'),
        containsAll(['... on User', '... on Post']),
      );
    });

    test('argument names inside parentheses', () {
      expect(at('{ me { friends(| ) } }'), ['first', 'after']);
      expect(at('{ me { friends(first: 1, af|) } }'), ['after']);
      expect(at('{ me { friends(first: |) } }'), isEmpty);
    });

    test('insert text opens a selection for object fields', () {
      final c = graphqlComplete(schema, '{ m }', 3)!;
      expect(c.items.single.text, 'me {');
      expect(c.replaceFrom, 2);
    });

    test('nothing inside strings, unknown fields or outside selections', () {
      expect(at('{ user(id: "|") }'), isEmpty);
      expect(at('{ nothing { | } }'), isEmpty);
      expect(at('|'), isEmpty);
    });
  });
}
