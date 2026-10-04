import 'dart:convert';

import 'package:postit_core/postit_core.dart';
import 'package:test/test.dart';

ResponseFacts facts({
  int status = 200,
  String body = '{"id":7,"name":"Rex","tags":["a","b"],"owner":{"age":4}}',
  int timeMs = 120,
}) => ResponseFacts(
  status: status,
  headers: const [('Content-Type', 'application/json'), ('X-N', '5')],
  body: body,
  timeMs: timeMs,
);

TestResult run(Assertion a, [ResponseFacts? f]) => a.evaluate(f ?? facts());

void main() {
  group('jsonPath', () {
    final doc = jsonDecode(
      '{"a":{"b":[{"c":1},{"c":2}]},"k":"v","list":[1,2,3]}',
    );
    test('keys, indexes and wildcards', () {
      expect(jsonPath(doc, r'$.k'), ['v']);
      expect(jsonPath(doc, r'$.a.b[1].c'), [2]);
      expect(jsonPath(doc, r'$.a.b[-1].c'), [2]);
      expect(jsonPath(doc, r"$['a']['b'][0]"), [
        {'c': 1},
      ]);
      expect(jsonPath(doc, r'$.a.b[*].c'), [1, 2]);
      expect(jsonPath(doc, r'$.list.*'), [1, 2, 3]);
    });
    test('recursive descent and misses', () {
      expect(jsonPath(doc, r'$..c'), [1, 2]);
      expect(jsonPath(doc, r'$.missing.x'), isEmpty);
      expect(jsonPath(doc, r'$.list[9]'), isEmpty);
      expect(jsonPath(doc, r'$'), [doc]);
    });
    test('unsupported syntax throws instead of matching nothing', () {
      expect(() => jsonPath(doc, r'$.list[?(@>1)]'), throwsFormatException);
      expect(() => jsonPath(doc, 'a.b'), throwsFormatException);
      expect(() => jsonPath(doc, r'$.a['), throwsFormatException);
    });
  });

  group('validateJsonSchema', () {
    const schema = {
      'type': 'object',
      'required': ['id', 'name'],
      'properties': {
        'id': {'type': 'integer', 'minimum': 1},
        'name': {'type': 'string', 'minLength': 2, 'pattern': '^[A-Z]'},
        'tags': {
          'type': 'array',
          'items': {'type': 'string'},
          'maxItems': 2,
        },
        'kind': {
          'enum': ['dog', 'cat'],
        },
      },
      'additionalProperties': false,
    };
    test('accepts a matching document', () {
      expect(
        validateJsonSchema({
          'id': 1,
          'name': 'Rex',
          'tags': ['a'],
          'kind': 'dog',
        }, schema),
        isEmpty,
      );
    });
    test('reports each problem with its location', () {
      final errors = validateJsonSchema({
        'id': 0,
        'name': 'x',
        'tags': ['a', 2, 'c'],
        'kind': 'cow',
        'extra': 1,
      }, schema);
      expect(errors, hasLength(greaterThanOrEqualTo(6)));
      expect(errors.join('|'), contains(r'$.id'));
      expect(errors.join('|'), contains(r'$.tags[1]'));
      expect(errors.join('|'), contains('unexpected "extra"'));
    });
    test('missing required and wrong type', () {
      expect(
        validateJsonSchema({'id': 'x'}, schema).join('|'),
        allOf(
          contains('missing required "name"'),
          contains('expected integer'),
        ),
      );
    });
    test('anyOf, oneOf, allOf', () {
      expect(
        validateJsonSchema(5, {
          'anyOf': [
            {'type': 'string'},
            {'type': 'integer'},
          ],
        }),
        isEmpty,
      );
      expect(
        validateJsonSchema(5, {
          'oneOf': [
            {'type': 'integer'},
            {'minimum': 1},
          ],
        }),
        isNotEmpty,
      );
      expect(
        validateJsonSchema(5, {
          'allOf': [
            {'minimum': 1},
            {'maximum': 3},
          ],
        }),
        hasLength(1),
      );
    });
  });

  group('assertions', () {
    test('status and response time', () {
      expect(
        run(const Assertion(target: AssertionTarget.status, value: '200'))
            .passed,
        isTrue,
      );
      final bad = run(
        const Assertion(
          target: AssertionTarget.status,
          op: AssertionOp.lt,
          value: '200',
        ),
      );
      expect(bad.failed, isTrue);
      expect(bad.message, 'Got 200');
      expect(
        run(
          const Assertion(
            target: AssertionTarget.responseTime,
            op: AssertionOp.lte,
            value: '500',
          ),
        ).passed,
        isTrue,
      );
    });

    test('a non-numeric value fails with a clear message', () {
      final r = run(
        const Assertion(target: AssertionTarget.status, value: 'ok'),
      );
      expect(r.failed, isTrue);
      expect(r.message, contains('not a number'));
    });

    test('headers are case-insensitive', () {
      Assertion h(AssertionOp op, [String v = '']) => Assertion(
        target: AssertionTarget.header,
        name: 'content-type',
        op: op,
        value: v,
      );
      expect(run(h(AssertionOp.exists)).passed, isTrue);
      expect(run(h(AssertionOp.contains, 'json')).passed, isTrue);
      expect(run(h(AssertionOp.eq, 'text/plain')).failed, isTrue);
      expect(
        run(
          const Assertion(
            target: AssertionTarget.header,
            name: 'X-Missing',
            op: AssertionOp.notExists,
          ),
        ).passed,
        isTrue,
      );
      expect(
        run(
          const Assertion(
            target: AssertionTarget.header,
            name: 'X-N',
            op: AssertionOp.gt,
            value: '4',
          ),
        ).passed,
        isTrue,
      );
    });

    test('jsonPath compares typed values', () {
      Assertion j(String path, AssertionOp op, [String v = '']) => Assertion(
        target: AssertionTarget.jsonPath,
        name: path,
        op: op,
        value: v,
      );
      expect(run(j(r'$.id', AssertionOp.eq, '7')).passed, isTrue);
      expect(run(j(r'$.id', AssertionOp.eq, '8')).failed, isTrue);
      expect(run(j(r'$.name', AssertionOp.eq, 'Rex')).passed, isTrue);
      expect(run(j(r'$.tags', AssertionOp.contains, 'a')).passed, isTrue);
      expect(run(j(r'$.tags', AssertionOp.eq, '["a","b"]')).passed, isTrue);
      expect(run(j(r'$.owner.age', AssertionOp.gte, '4')).passed, isTrue);
      expect(run(j(r'$.name', AssertionOp.matches, r'^R.x$')).passed, isTrue);
      expect(run(j(r'$.nope', AssertionOp.exists)).failed, isTrue);
      expect(run(j(r'$.nope', AssertionOp.notExists)).passed, isTrue);
      expect(
        run(j(r'$.nope', AssertionOp.eq, '1')).message,
        contains('missing'),
      );
    });

    test('jsonPath on a non-JSON body and bad paths fail, not throw', () {
      const a = Assertion(
        target: AssertionTarget.jsonPath,
        name: r'$.x',
        op: AssertionOp.exists,
      );
      expect(run(a, facts(body: 'plain')).message, contains('not JSON'));
      final bad = run(a.copyWith(name: 'x'));
      expect(bad.failed, isTrue);
    });

    test('body contains and regex', () {
      expect(
        run(
          const Assertion(
            target: AssertionTarget.body,
            op: AssertionOp.contains,
            value: 'Rex',
          ),
        ).passed,
        isTrue,
      );
      expect(
        run(
          const Assertion(
            target: AssertionTarget.body,
            op: AssertionOp.matches,
            value: r'"id":\d+',
          ),
        ).passed,
        isTrue,
      );
    });

    test('schema assertion', () {
      const ok = Assertion(
        target: AssertionTarget.schema,
        value: '{"type":"object","required":["id"]}',
      );
      expect(run(ok).passed, isTrue);
      final bad = run(ok.copyWith(value: '{"required":["zzz"]}'));
      expect(bad.failed, isTrue);
      expect(bad.message, contains('zzz'));
      expect(run(ok.copyWith(value: '{')).message, contains('not valid JSON'));
    });

    test('variables in the value are resolved first', () {
      const a = Assertion(target: AssertionTarget.status, value: '{{code}}');
      final r = a.evaluate(
        facts(),
        resolve: (s) => s.replaceAll('{{code}}', '200'),
      );
      expect(r.passed, isTrue);
      expect(r.name, 'Status code equals 200');
    });

    test('json round trip keeps order and drops unknown targets', () {
      const list = [
        Assertion(target: AssertionTarget.status, value: '201'),
        Assertion(
          target: AssertionTarget.jsonPath,
          name: r'$.id',
          op: AssertionOp.exists,
          enabled: false,
        ),
      ];
      final json = jsonDecode(jsonEncode(Assertion.listToJson(list)));
      (json as List).add({'target': 'future'});
      final back = Assertion.listFromJson(json);
      expect(back, hasLength(2));
      expect(back[1].enabled, isFalse);
      expect(back[1].op, AssertionOp.exists);
    });

    test('requests keep assertions through toData/fromData', () {
      const item = HttpRequestItem(
        id: 'i',
        name: 'n',
        assertions: [Assertion(target: AssertionTarget.status, value: '200')],
      );
      final back = HttpRequestItem.fromData(
        id: 'i',
        name: 'n',
        data: jsonDecode(jsonEncode(item.toData())) as Map<String, Object?>,
      );
      expect(back.assertions.single.value, '200');
      expect(back.extra.containsKey('assertions'), isFalse);
    });
  });
}
