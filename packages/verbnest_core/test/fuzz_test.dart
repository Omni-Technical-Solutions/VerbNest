import 'dart:convert';
import 'dart:io' show Platform;
import 'dart:math';

import 'package:test/test.dart';
import 'package:verbnest_core/src/graphql/lexer.dart' show lexGraphql;
import 'package:verbnest_core/verbnest_core.dart';

/// Parsers that read text from the network or from files must reject bad input
/// with a [FormatException] (or return nothing), never with a cast, range or
/// state error (security review S10, plan phase F). Inputs are generated from a
/// fixed seed so a failure repeats.
const _alphabet =
    '{}[]()<>"\'\\/:;,.=\$@#!?*&|^~`+-_ \n\t\r0123456789abcXYZ\u0000é中';

String _random(Random r, int max) => String.fromCharCodes([
  for (var i = r.nextInt(max); i > 0; i--)
    _alphabet.codeUnitAt(r.nextInt(_alphabet.length)),
]);

/// [seed] with a few characters changed, removed, inserted or repeated.
String _mutate(String seed, Random r) {
  final b = StringBuffer();
  for (var i = 0; i < seed.length; i++) {
    switch (r.nextInt(25)) {
      case 0:
        break; // drop
      case 1:
        b.write(_random(r, 4));
        b.write(seed[i]);
      case 2:
        b.write(seed[i] * (2 + r.nextInt(30)));
      case 3:
        return b.toString(); // truncate
      default:
        b.write(seed[i]);
    }
  }
  return b.toString();
}

void _fuzz(
  String name,
  List<String> seeds,
  void Function(String input) run, {
  int? rounds,
}) {
  // FUZZ_ROUNDS=50000 dart test test/fuzz_test.dart runs a longer search.
  final count =
      rounds ?? int.tryParse(Platform.environment['FUZZ_ROUNDS'] ?? '') ?? 600;
  test('$name never fails with anything but a FormatException', () {
    final r = Random(20261021);
    for (var i = 0; i < count; i++) {
      final input = i.isEven || seeds.isEmpty
          ? _random(r, 120)
          : _mutate(seeds[r.nextInt(seeds.length)], r);
      try {
        run(input);
      } on FormatException {
        // Rejecting bad input is fine.
      } on Object catch (e, st) {
        fail('$name threw ${e.runtimeType} for ${input.codeUnits}:\n$e\n$st');
      }
    }
  });
}

void main() {
  _fuzz(
    'JSONPath',
    [
      r'$.a.b[0]',
      r'$..book[?(@.price<10)].title',
      r"$['a b']['c'][1:3]",
      r'$.store.*',
    ],
    (s) => jsonPath({
      'a': {
        'b': [1, 2, 3],
      },
      'store': {'x': 1, 'y': 2},
    }, s),
  );

  _fuzz('JSON schema validation', [
    '{"type":"object","properties":{"a":{"type":"integer","minimum":1}}}',
  ], (s) => validateJsonSchema({'a': 'x', 'b': 3}, jsonDecode(s)));

  _fuzz('body filter (JSON)', [r'$.a', r'$..b[0]'], (s) {
    filterBody('{"a":[1,{"b":[2,3]}]}', BodyKind.json, s);
  });

  _fuzz('body filter (XML)', ['//a/b', '/root/a[1]', '//*[@id="1"]'], (s) {
    filterBody('<root><a id="1"><b>t</b></a></root>', BodyKind.xml, s);
  });

  _fuzz('data file', [
    'a,b\n1,2\n3,4',
    '[{"a":1},{"a":2}]',
    'a\tb\n1\t2',
  ], (s) => parseDataFile(s));
  _fuzz('data file (JSON name)', ['[{"a":1}]', '{"a":1}'], (s) {
    parseDataFile(s, fileName: 'rows.json');
  });

  _fuzz(
    'GraphQL lexer and operation names',
    ['query Q(\$a: Int) { me { id name } }', 'mutation { a(b: "c\\n") }'],
    (s) {
      lexGraphql(s);
      graphqlOperationNames(s);
    },
  );

  _fuzz('GraphQL schema (SDL)', [
    'type Query { a(x: Int = 1): [String!]! }\nenum E { A B }\ninput I { f: Int }',
    'interface N { id: ID } union U = A | B scalar S directive @d on FIELD',
  ], (s) => GraphqlSchema.fromSdl(s));

  _fuzz('results table (JSON)', [
    '[{"a":1,"b":{"c":2}},{"a":3,"b":null}]',
    '{"rows":[{"x":1}],"n":2}',
    '[[1,2],[3,4]]',
  ], (s) => readTable(s, 'application/json'));
  _fuzz('results table (XML)', [
    '<r><i a="1"><n>x</n></i><i a="2"/></r>',
  ], (s) => readTable(s, 'application/xml'));
  _fuzz('results table (CSV)', [
    'a,b\n1,"x, y"\n3,4',
    'a\tb\n1\t2',
  ], (s) => readTable(s, 'text/csv'));

  _fuzz(
    'Set-Cookie',
    [
      'a=b; Path=/; Max-Age=60; HttpOnly',
      'sid=1; Domain=example.com; Expires=Wed, 21 Oct 2026 07:28:00 GMT; Secure',
    ],
    (s) {
      final jar = CookieJar();
      jar.storeFromResponse(Uri.parse('https://api.example.com/x'), [s]);
      jar.cookieHeader(Uri.parse('https://api.example.com/y'));
    },
  );
}
