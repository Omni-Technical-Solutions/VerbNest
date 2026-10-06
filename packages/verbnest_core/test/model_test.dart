import 'dart:convert';

import 'package:verbnest_core/verbnest_core.dart';
import 'package:test/test.dart';

Object? roundTrip(Object? json) => jsonDecode(jsonEncode(json));

void main() {
  group('UrlText', () {
    test('params keep order, duplicates and empty values', () {
      final p = UrlText.params('https://x/a?b=1&b=2&c=&d#frag');
      expect(p.map((e) => '${e.key}=${e.value}'), ['b=1', 'b=2', 'c=', 'd=']);
    });

    test('does not decode or re-encode', () {
      final p = UrlText.params('/x?q=a%20b&r={{v}}');
      expect(p.map((e) => e.value), ['a%20b', '{{v}}']);
    });

    test('withParams writes enabled rows only and keeps the fragment', () {
      final url = UrlText.withParams('https://x/a?old=1#top', const [
        KeyValue(key: 'a', value: '1'),
        KeyValue(key: 'b', value: '2', enabled: false),
        KeyValue(key: 'c', value: 'x y'),
      ]);
      expect(url, 'https://x/a?a=1&c=x y#top');
    });

    test('withParams with nothing enabled drops the question mark', () {
      expect(UrlText.withParams('https://x/a?b=1', const []), 'https://x/a');
    });

    test('pathVariables ignores ports and the query', () {
      expect(
        UrlText.pathVariables(
          'http://h:8080/pets/:petId/owners/:ownerId?x=:no',
        ),
        ['petId', 'ownerId'],
      );
      expect(UrlText.pathVariables('{{base}}/a/:id/b/:id'), ['id']);
      expect(UrlText.pathVariables('localhost:3000'), isEmpty);
    });

    test('applyPathVariables substitutes known names only', () {
      expect(
        UrlText.applyPathVariables('http://h:80/p/:a/:b?q=1', {'a': '7'}),
        'http://h:80/p/7/:b?q=1',
      );
    });
  });

  group('Auth', () {
    test('known types round-trip', () {
      for (final auth in <Auth>[
        const InheritAuth(),
        const NoAuth(),
        const BearerAuth(token: '{{t}}'),
        const BasicAuth(username: 'u', password: 'p'),
        const ApiKeyAuth(key: 'k', value: 'v', addTo: ApiKeyLocation.query),
        const OAuth2Auth(
          grant: OAuth2Grant.password,
          tokenUrl: 'https://t/token',
          clientId: 'id',
          clientSecret: 's',
          scope: 'a b',
          username: 'u',
          password: 'p',
          clientAuthInBody: true,
        ),
        const OAuth2Auth(grant: OAuth2Grant.clientCredentials),
      ]) {
        final back = Auth.fromJson((roundTrip(auth.toJson()) as Map).cast());
        expect(back.toJson(), auth.toJson());
        expect(back.runtimeType, auth.runtimeType);
      }
    });

    test('unknown types are preserved', () {
      final raw = {'type': 'oauth2', 'grantType': 'device_code'};
      final auth = Auth.fromJson(raw);
      expect(auth, isA<RawAuth>());
      expect(auth.toJson(), raw);
    });

    test('new auth types round-trip through JSON', () {
      final all = <Auth>[
        const DigestAuth(username: 'u', password: 'p'),
        const JwtAuth(
          algorithm: JwtAlgorithm.hs384,
          secret: 's',
          payload: '{"a":1}',
          prefix: 'JWT',
        ),
        const AwsV4Auth(
          accessKey: 'a',
          secretKey: 'k',
          region: 'r',
          service: 's',
          sessionToken: 't',
        ),
        const OAuth2Auth(
          grant: OAuth2Grant.authorizationCode,
          authUrl: 'https://a',
          tokenUrl: 'https://t',
          clientId: 'c',
          usePkce: false,
        ),
        const OAuth2Auth(grant: OAuth2Grant.implicit, authUrl: 'https://a'),
      ];
      for (final a in all) {
        final back = Auth.fromJson(a.toJson());
        expect(back.runtimeType, a.runtimeType);
        expect(back.toJson(), a.toJson());
      }
      expect((Auth.fromJson(all[3].toJson()) as OAuth2Auth).usePkce, isFalse);
      expect((all[3] as OAuth2Auth).interactive, isTrue);
    });

    test('inherit resolves up the chain', () {
      const bearer = BearerAuth(token: 't');
      expect(
        effectiveAuth(const InheritAuth(), [const InheritAuth(), bearer]),
        bearer,
      );
      expect(effectiveAuth(const InheritAuth(), const []), isA<NoAuth>());
      expect(effectiveAuth(const NoAuth(), [bearer]), isA<NoAuth>());
    });
  });

  group('RequestBody', () {
    test('each mode round-trips', () {
      final bodies = <RequestBody>[
        const NoBody(),
        const RawBody(RawBodyLanguage.json, '{"a":1}'),
        const RawBody(RawBodyLanguage.xml, '<a/>'),
        const UrlEncodedBody([KeyValue(key: 'a', value: '1')]),
        const FormDataBody([KeyValue(key: 'f', type: KeyValueType.file)]),
        const BinaryBody('att1'),
      ];
      for (final b in bodies) {
        final back = RequestBody.fromJson(
          (roundTrip(b.toJson()) as Map).cast(),
        );
        expect(back.mode, b.mode);
        expect(back.toJson(), b.toJson());
      }
    });

    test('default content types', () {
      expect(
        const RawBody(RawBodyLanguage.json, '').defaultContentType,
        'application/json',
      );
      expect(const NoBody().defaultContentType, isNull);
      expect(const FormDataBody([]).defaultContentType, isNull);
    });
  });

  group('HttpRequestItem', () {
    final item = HttpRequestItem(
      id: '01A',
      name: 'Create pet',
      method: 'POST',
      url: '{{baseUrl}}/pets/:petId?verbose=true',
      params: const [KeyValue(key: 'verbose', value: 'true')],
      pathVars: const [KeyValue(key: 'petId', value: '{{petId}}')],
      headers: const [
        KeyValue(key: 'Content-Type', value: 'application/json'),
        KeyValue(
          key: 'X-Trace',
          value: 'x',
          enabled: false,
          description: 'debug',
        ),
      ],
      body: const RawBody(RawBodyLanguage.json, '{}'),
      auth: const BearerAuth(token: '{{t}}'),
      settings: const RequestSettings(timeoutMs: 5000, verifyTls: false),
      scripts: const Scripts(pre: 'a', post: 'b'),
      description: 'Creates a pet',
    );

    HttpRequestItem reload(HttpRequestItem i) => HttpRequestItem.fromData(
      id: i.id,
      name: i.name,
      data: (roundTrip(i.toData()) as Map).cast(),
      auth: (roundTrip(i.auth.toJson()) as Map).cast(),
      scripts: (roundTrip(i.scripts.toJson()) as Map).cast(),
      description: i.description,
    );

    test('survives a JSON round trip', () {
      final back = reload(item);
      expect(back.toData(), item.toData());
      expect(back.headers, item.headers);
      expect(back.auth.toJson(), item.auth.toJson());
      expect(back.scripts.post, 'b');
      expect(back.settings.verifyTls, isFalse);
    });

    test('preserves unknown keys from a newer version', () {
      final back = HttpRequestItem.fromData(
        id: '1',
        name: 'n',
        data: {
          'method': 'GET',
          'url': '/',
          'futureFlag': {'x': 1},
        },
      );
      expect(back.toData()['futureFlag'], {'x': 1});
    });

    test('defaults for an empty document', () {
      final r = HttpRequestItem.fromData(id: '1', name: 'n', data: {});
      expect(r.method, 'GET');
      expect(r.auth, isA<InheritAuth>());
      expect(r.body, isA<NoBody>());
    });
  });
}
