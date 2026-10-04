import 'dart:math';

import 'package:postit_core/postit_core.dart';
import 'package:test/test.dart';

Variable v(String k, String val, {bool secret = false, bool enabled = true}) =>
    Variable(key: k, value: val, secret: secret, enabled: enabled);

void main() {
  group('precedence', () {
    test('local > data > environment > collection > global', () {
      final scopes = VariableScopes(
        local: [v('a', 'local')],
        data: [v('a', 'data'), v('b', 'data')],
        environment: [v('a', 'env'), v('b', 'env'), v('c', 'env')],
        collection: [
          v('a', 'col'),
          v('b', 'col'),
          v('c', 'col'),
          v('d', 'col'),
        ],
        global: [
          v('a', 'g'),
          v('b', 'g'),
          v('c', 'g'),
          v('d', 'g'),
          v('e', 'g'),
        ],
      );
      final r = VariableResolver(scopes);
      expect(r.resolve('{{a}}{{b}}{{c}}{{d}}{{e}}').value, 'localdataenvcolg');
    });

    test('disabled variables are invisible', () {
      final scopes = VariableScopes(
        environment: [v('a', 'off', enabled: false)],
        global: [v('a', 'on')],
      );
      expect(VariableResolver(scopes).resolve('{{a}}').value, 'on');
    });

    test('visible() lists each name once with its winning scope', () {
      final scopes = VariableScopes(
        environment: [v('a', '1')],
        global: [v('a', '2'), v('b', '3')],
      );
      final visible = scopes.visible();
      expect(visible.map((e) => e.variable.key), ['a', 'b']);
      expect(visible.first.scope, VariableScope.environment);
    });
  });

  group('recursion', () {
    test('resolves nested references and trims whitespace', () {
      final scopes = VariableScopes(
        environment: [v('base', 'https://x'), v('url', '{{ base }}/p')],
      );
      expect(VariableResolver(scopes).resolve('{{url}}').value, 'https://x/p');
    });

    test('cycle names the chain', () {
      final scopes = VariableScopes(
        environment: [v('a', '{{b}}'), v('b', '{{a}}')],
      );
      expect(
        () => VariableResolver(scopes).resolve('{{a}}'),
        throwsA(
          isA<VariableCycleException>().having((e) => e.chain, 'chain', [
            'a',
            'b',
            'a',
          ]),
        ),
      );
    });

    test('depth beyond 10 fails', () {
      final vars = [
        for (var i = 0; i < 12; i++) v('v$i', '{{v${i + 1}}}'),
        v('v12', 'end'),
      ];
      final r = VariableResolver(VariableScopes(environment: vars));
      expect(() => r.resolve('{{v0}}'), throwsA(isA<VariableCycleException>()));
    });
  });

  group('unresolved', () {
    test('left verbatim and reported', () {
      final r = VariableResolver(VariableScopes());
      final result = r.resolve('x/{{missing}}/{{\$nope}}');
      expect(result.value, 'x/{{missing}}/{{\$nope}}');
      expect(result.unresolved, {'missing', r'$nope'});
      expect(result.hasUnresolved, isTrue);
    });
  });

  group('secrets', () {
    final scopes = VariableScopes(
      environment: [v('key', 's3cret', secret: true), v('h', 'Bearer {{key}}')],
    );

    test('resolve injects real value', () {
      final result = VariableResolver(scopes).resolve('{{h}}');
      expect(result.value, 'Bearer s3cret');
      expect(result.secretNames, {'key'});
    });

    test('resolveMasked never leaks the value', () {
      final result = VariableResolver(scopes).resolveMasked('{{h}}');
      expect(result.value, 'Bearer ••••••');
      expect(result.value, isNot(contains('s3cret')));
    });
  });

  group('dynamic variables', () {
    test('each occurrence gets its own value', () {
      final r = VariableResolver(VariableScopes());
      final out = r.resolve(r'{{$guid}}|{{$guid}}').value.split('|');
      expect(out[0], isNot(out[1]));
      expect(
        out[0],
        matches(
          RegExp(
            r'^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$',
          ),
        ),
      );
    });

    test('timestamps use the injected clock', () {
      final dyn = DynamicVariables(
        random: Random(1),
        clock: () => DateTime.utc(2026, 1, 2, 3, 4, 5),
      );
      final r = VariableResolver(VariableScopes(), dynamic: dyn);
      expect(r.resolve(r'{{$isoTimestamp}}').value, '2026-01-02T03:04:05.000Z');
      expect(r.resolve(r'{{$timestamp}}').value, '1767323045');
    });

    test('random helpers produce well-formed values', () {
      final r = VariableResolver(VariableScopes());
      expect(
        int.parse(r.resolve(r'{{$randomInt}}').value),
        inInclusiveRange(0, 1000),
      );
      expect(r.resolve(r'{{$randomEmail}}').value, endsWith('@example.com'));
      expect(r.resolve(r'{{$randomFirstName}}').value, isNotEmpty);
    });
  });
}
