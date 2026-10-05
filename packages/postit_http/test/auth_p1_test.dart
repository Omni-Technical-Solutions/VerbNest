import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:postit_core/postit_core.dart';
import 'package:postit_http/postit_http.dart';
import 'package:test/test.dart';

HttpRequestItem item({
  String url = 'http://127.0.0.1/x',
  String method = 'GET',
  Auth auth = const NoAuth(),
  RequestBody body = const NoBody(),
}) => HttpRequestItem(
  id: 'i',
  name: 'n',
  method: method,
  url: url,
  auth: auth,
  body: body,
);

VariableResolver vars([List<Variable> env = const []]) =>
    VariableResolver(VariableScopes(environment: env));

/// The public key from the AWS Signature V4 documentation, written in parts
/// so secret scanners do not mistake it for a real credential.
const awsExampleSecret =
    'wJalrXUtnFEMI/'
    'K7MDENG+'
    'bPxRfiCYEXAMPLEKEY';

void main() {
  group('JWT', () {
    test('matches the jwt.io HS256 example', () {
      final t = signJwt(
        const JwtAuth(
          secret: 'your-256-bit-secret',
          payload: '{"sub":"1234567890","name":"John Doe","iat":1516239022}',
        ),
      );
      expect(
        t,
        'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.'
        'eyJzdWIiOiIxMjM0NTY3ODkwIiwibmFtZSI6IkpvaG4gRG9lIiwiaWF0IjoxNTE2MjM5MDIyfQ.'
        'SflKxwRJSMeKKF2QT4fwpMeJf36POk6yJV_adQssw5c',
      );
    });

    test('adds iat and signs with the chosen hash', () {
      final t = signJwt(
        const JwtAuth(
          algorithm: JwtAlgorithm.hs512,
          secret: 's',
          payload: '{"a":1}',
        ),
        now: DateTime.fromMillisecondsSinceEpoch(5000000, isUtc: true),
      );
      final parts = t.split('.');
      Map<String, Object?> dec(String p) =>
          jsonDecode(utf8.decode(base64Url.decode(base64Url.normalize(p))))
              as Map<String, Object?>;
      expect(dec(parts[0])['alg'], 'HS512');
      expect(dec(parts[1]), {'a': 1, 'iat': 5000});
      final mac = Hmac(
        sha512,
        utf8.encode('s'),
      ).convert(utf8.encode('${parts[0]}.${parts[1]}'));
      expect(parts[2], base64Url.encode(mac.bytes).replaceAll('=', ''));
    });

    test('a bad payload is a clear build error', () async {
      await expectLater(
        RequestBuilder().build(
          item(
            auth: const JwtAuth(secret: 's', payload: '[1]'),
          ),
          vars(),
        ),
        throwsA(isA<RequestBuildError>()),
      );
    });

    test('the builder sets the Authorization header and masks it', () async {
      final p = await RequestBuilder(clock: () => DateTime.utc(2025)).build(
        item(
          auth: const JwtAuth(
            secret: '{{k}}',
            payload: '{"u":"{{who}}"}',
            prefix: 'JWT',
          ),
        ),
        vars([
          const Variable(key: 'k', value: 'topsecret'),
          const Variable(key: 'who', value: 'ann'),
        ]),
      );
      final auth = p.spec.headers.firstWhere((h) => h.$1 == 'Authorization');
      expect(auth.$2, startsWith('JWT eyJ'));
      expect(
        p.masker.headerValue('Authorization', auth.$2),
        Masker.placeholder,
      );
    });
  });

  group('AWS SigV4', () {
    test('matches the AWS get-vanilla test vector', () {
      final h = signAwsV4(
        const AwsV4Auth(
          accessKey: 'AKIDEXAMPLE',
          secretKey: awsExampleSecret,
          region: 'us-east-1',
          service: 'service',
        ),
        method: 'GET',
        url: Uri.parse('https://example.amazonaws.com/'),
        headers: const [],
        body: const [],
        now: DateTime.utc(2015, 8, 30, 12, 36),
      );
      expect(h.first, ('X-Amz-Date', '20150830T123600Z'));
      expect(
        h.last.$2,
        'AWS4-HMAC-SHA256 Credential=AKIDEXAMPLE/20150830/us-east-1/service/aws4_request, '
        'SignedHeaders=host;x-amz-date, '
        'Signature=5fa00fa31553b73ebf1942676e86291e8372ff2a2260956d9b8aae1d763fbf31',
      );
    });

    test('matches the AWS get-vanilla-query-order test vector', () {
      final h = signAwsV4(
        const AwsV4Auth(
          accessKey: 'AKIDEXAMPLE',
          secretKey: awsExampleSecret,
          region: 'us-east-1',
          service: 'service',
        ),
        method: 'GET',
        url: Uri.parse(
          'https://example.amazonaws.com/?Param2=value2&Param1=value1',
        ),
        headers: const [],
        body: const [],
        now: DateTime.utc(2015, 8, 30, 12, 36),
      );
      expect(
        h.last.$2,
        endsWith(
          'Signature=b97d918cfa904a5beff61c982a1b6f458b799221646efd99d3219ec94cdf2500',
        ),
      );
    });

    test('a session token is signed and sent', () {
      final h = signAwsV4(
        const AwsV4Auth(
          accessKey: 'A',
          secretKey: 'S',
          region: 'r',
          service: 'svc',
          sessionToken: 'TOKEN',
        ),
        method: 'POST',
        url: Uri.parse('http://localhost:9000/p'),
        headers: [('Content-Type', 'application/json')],
        body: utf8.encode('{}'),
        now: DateTime.utc(2025),
      );
      expect(h.any((e) => e == ('X-Amz-Security-Token', 'TOKEN')), isTrue);
      expect(
        h.last.$2,
        contains(
          'SignedHeaders=content-type;host;x-amz-date;x-amz-security-token',
        ),
      );
    });

    test('the builder signs the final request and masks the secret', () async {
      final p = await RequestBuilder(clock: () => DateTime.utc(2025)).build(
        item(
          method: 'POST',
          body: const RawBody(RawBodyLanguage.json, '{"a":1}'),
          auth: const AwsV4Auth(
            accessKey: 'AK',
            secretKey: '{{sk}}',
            region: 'eu-west-1',
            service: 's3',
          ),
        ),
        vars([const Variable(key: 'sk', value: 'verysecret')]),
      );
      final names = p.spec.headers.map((h) => h.$1).toList();
      expect(
        names,
        containsAll(['X-Amz-Date', 'Authorization', 'Content-Type']),
      );
      expect(
        p.masker.maskText('x verysecret y'),
        isNot(contains('verysecret')),
      );
    });
  });

  group('Digest', () {
    test('matches the RFC 2617 example', () {
      final c = DigestChallenge.find([
        'Digest realm="testrealm@host.com", qop="auth,auth-int", '
            'nonce="dcd98b7102dd2f0e8b11d0f600bfb0c093", '
            'opaque="5ccc069c403ebaf9f0171e9517f40e41"',
      ])!;
      final v = digestAuthorization(
        c,
        const DigestAuth(username: 'Mufasa', password: 'Circle Of Life'),
        method: 'GET',
        uri: '/dir/index.html',
        cnonce: '0a4f113b',
      );
      expect(v, contains('response="6629fae49393a05397450978507c4ef1"'));
      expect(v, contains('qop=auth, nc=00000001, cnonce="0a4f113b"'));
      expect(v, contains('opaque="5ccc069c403ebaf9f0171e9517f40e41"'));
    });

    test('matches the RFC 7616 SHA-256 example', () {
      final c = DigestChallenge.find([
        'Digest realm="http-auth@example.org", qop="auth, auth-int", '
            'algorithm=SHA-256, '
            'nonce="7ypf/xlj9XXwfDPEoM4URrv/xwf94BcCAzFZH4GiTo0v", '
            'opaque="FQhe/qaU925kfnzjCev0ciny7QMkPqMAFRtzCUYo5tdS"',
      ])!;
      final v = digestAuthorization(
        c,
        const DigestAuth(username: 'Mufasa', password: 'Circle of Life'),
        method: 'GET',
        uri: '/dir/index.html',
        cnonce: 'f2/wE4q74E6zIJEtWaHKaf5wv/H5QzzpXusqGemxURZJ',
      );
      expect(
        v,
        contains(
          'response="753927fa0e85d155564e2e272a28d1802ca10daf4496794697cf8db5856cb6c1"',
        ),
      );
    });

    test('finds Digest among several challenges and ignores others', () {
      expect(DigestChallenge.find(['Basic realm="x"']), isNull);
      final c = DigestChallenge.find(['Digest realm="a b", nonce="n1"'])!;
      expect(c.realm, 'a b');
      expect(c.nonce, 'n1');
    });

    test('sendPrepared answers a 401 challenge once', () async {
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      addTearDown(() => server.close(force: true));
      final seen = <String?>[];
      server.listen((req) {
        final a = req.headers.value('authorization');
        seen.add(a);
        if (a == null) {
          req.response
            ..statusCode = 401
            ..headers.set(
              'WWW-Authenticate',
              'Digest realm="r", qop="auth", nonce="abc", opaque="o"',
            );
        } else {
          req.response.statusCode = 200;
          req.response.write('welcome');
        }
        req.response.close();
      });
      final p = await RequestBuilder().build(
        item(
          url: 'http://127.0.0.1:${server.port}/dir?x=1',
          auth: const DigestAuth(username: 'u', password: '{{pw}}'),
        ),
        vars([const Variable(key: 'pw', value: 'p')]),
      );
      final r = await sendPrepared(HttpEngine(), p);
      expect(r.status, 200);
      expect(seen.length, 2);
      expect(seen[0], isNull);
      expect(seen[1], startsWith('Digest username="u"'));
      expect(seen[1], contains('uri="/dir?x=1"'));
    });

    test('no retry for other auth or when the retry is also refused', () async {
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      addTearDown(() => server.close(force: true));
      var calls = 0;
      server.listen((req) {
        calls++;
        req.response
          ..statusCode = 401
          ..headers.set('WWW-Authenticate', 'Digest realm="r", nonce="n"');
        req.response.close();
      });
      final url = 'http://127.0.0.1:${server.port}/';
      final plain = await RequestBuilder().build(item(url: url), vars());
      expect((await sendPrepared(HttpEngine(), plain)).status, 401);
      expect(calls, 1);
      final dig = await RequestBuilder().build(
        item(
          url: url,
          auth: const DigestAuth(username: 'u', password: 'p'),
        ),
        vars(),
      );
      expect((await sendPrepared(HttpEngine(), dig)).status, 401);
      expect(calls, 3);
    });
  });

  group('OAuth 2.0 in the browser', () {
    test('PKCE challenge matches the RFC 7636 example', () {
      expect(
        PkcePair.challengeFor('dBjftJeZ4CVP-mB92K27uhbUJU1p1r_wW1gFWFOEjXk'),
        'E9Melhoa2OwvFrEMTJguCHaoeK1t8URWbuGJSstw-cM',
      );
      final p = PkcePair.generate();
      expect(p.verifier.length, greaterThanOrEqualTo(43));
      expect(PkcePair.challengeFor(p.verifier), p.challenge);
    });

    Future<HttpServer> tokenServer(
      List<Map<String, String>> forms, {
      String body = '{"access_token":"AT","refresh_token":"RT","expires_in":3600,"token_type":"Bearer"}',
    }) async {
      final s = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      addTearDown(() => s.close(force: true));
      s.listen((req) async {
        final text = await utf8.decodeStream(req);
        forms.add(Uri.splitQueryString(text));
        forms.last['_auth'] = req.headers.value('authorization') ?? '';
        req.response.headers.contentType = ContentType.json;
        req.response.write(body);
        await req.response.close();
      });
      return s;
    }

    Future<void> hit(Uri u) async {
      final c = HttpClient();
      final r = await (await c.getUrl(u)).close();
      await r.drain<void>();
      c.close();
    }

    test('authorization code with PKCE exchanges the code', () async {
      final forms = <Map<String, String>>[];
      final ts = await tokenServer(forms);
      final auth = OAuth2Auth(
        grant: OAuth2Grant.authorizationCode,
        authUrl: 'https://idp.test/authorize?audience=api',
        tokenUrl: 'http://127.0.0.1:${ts.port}/token',
        clientId: 'cid',
        clientSecret: 'sec',
        scope: 'read write',
      );
      late Uri opened;
      final token = await authorizeInBrowser(
        HttpEngine(),
        auth,
        openUrl: (u) async {
          opened = u;
          final q = u.queryParameters;
          final redirect = Uri.parse(q['redirect_uri']!).replace(
            queryParameters: {'code': 'the-code', 'state': q['state']!},
          );
          unawaited(hit(redirect));
        },
      );
      final q = opened.queryParameters;
      expect(opened.host, 'idp.test');
      expect(q['audience'], 'api');
      expect(q['response_type'], 'code');
      expect(q['client_id'], 'cid');
      expect(q['scope'], 'read write');
      expect(q['code_challenge_method'], 'S256');
      expect(q['redirect_uri'], startsWith('http://127.0.0.1:'));

      final form = forms.single;
      expect(form['grant_type'], 'authorization_code');
      expect(form['code'], 'the-code');
      expect(form['redirect_uri'], q['redirect_uri']);
      expect(
        PkcePair.challengeFor(form['code_verifier']!),
        q['code_challenge'],
      );
      expect(form['_auth'], startsWith('Basic '));
      expect(token.accessToken, 'AT');
      expect(token.refreshToken, 'RT');
      expect(token.expiresAt, isNotNull);
    });

    test('without PKCE no challenge or verifier is sent', () async {
      final forms = <Map<String, String>>[];
      final ts = await tokenServer(forms);
      late Uri opened;
      await authorizeInBrowser(
        HttpEngine(),
        OAuth2Auth(
          grant: OAuth2Grant.authorizationCode,
          usePkce: false,
          authUrl: 'https://idp.test/a',
          tokenUrl: 'http://127.0.0.1:${ts.port}/t',
          clientId: 'c',
        ),
        openUrl: (u) async {
          opened = u;
          unawaited(
            hit(
              Uri.parse(u.queryParameters['redirect_uri']!).replace(
                queryParameters: {
                  'code': 'c1',
                  'state': u.queryParameters['state']!,
                },
              ),
            ),
          );
        },
      );
      expect(opened.queryParameters.containsKey('code_challenge'), isFalse);
      expect(forms.single.containsKey('code_verifier'), isFalse);
    });

    test('a wrong state or an error from the server is refused', () async {
      final forms = <Map<String, String>>[];
      final ts = await tokenServer(forms);
      OAuth2Auth auth() => OAuth2Auth(
        grant: OAuth2Grant.authorizationCode,
        authUrl: 'https://idp.test/a',
        tokenUrl: 'http://127.0.0.1:${ts.port}/t',
        clientId: 'c',
      );
      await expectLater(
        authorizeInBrowser(
          HttpEngine(),
          auth(),
          openUrl: (u) async => unawaited(
            hit(
              Uri.parse(u.queryParameters['redirect_uri']!)
                  .replace(queryParameters: {'code': 'c1', 'state': 'forged'}),
            ),
          ),
        ),
        throwsA(
          isA<OAuth2Error>().having((e) => e.message, 'm', contains('state')),
        ),
      );
      await expectLater(
        authorizeInBrowser(
          HttpEngine(),
          auth(),
          openUrl: (u) async => unawaited(
            hit(
              Uri.parse(u.queryParameters['redirect_uri']!).replace(
                queryParameters: {
                  'error': 'access_denied',
                  'state': u.queryParameters['state']!,
                },
              ),
            ),
          ),
        ),
        throwsA(
          isA<OAuth2Error>().having(
            (e) => e.message,
            'm',
            contains('access_denied'),
          ),
        ),
      );
      expect(forms, isEmpty);
    });

    test('implicit flow takes the token forwarded from the fragment', () async {
      Uri? redirect;
      final token = await authorizeInBrowser(
        HttpEngine(),
        const OAuth2Auth(
          grant: OAuth2Grant.implicit,
          authUrl: 'https://idp.test/a',
          clientId: 'c',
        ),
        openUrl: (u) async {
          expect(u.queryParameters['response_type'], 'token');
          redirect = Uri.parse(u.queryParameters['redirect_uri']!);
          final state = u.queryParameters['state']!;
          // The first page load carries no query and gets the forwarding page.
          final c = HttpClient();
          final page = await (await c.getUrl(redirect!)).close();
          final html = await utf8.decodeStream(page);
          expect(html, contains('location.hash'));
          c.close();
          unawaited(
            hit(
              redirect!.replace(
                queryParameters: {
                  'access_token': 'IMPL',
                  'expires_in': '60',
                  'state': state,
                },
              ),
            ),
          );
        },
      );
      expect(token.accessToken, 'IMPL');
      expect(token.expiresAt, isNotNull);
    });

    test('cancelling stops the wait and frees the port', () async {
      final cancel = CancelToken();
      Uri? redirect;
      final f = authorizeInBrowser(
        HttpEngine(),
        const OAuth2Auth(
          grant: OAuth2Grant.implicit,
          authUrl: 'https://idp.test/a',
          clientId: 'c',
        ),
        cancel: cancel,
        openUrl: (u) async {
          redirect = Uri.parse(u.queryParameters['redirect_uri']!);
          Timer(const Duration(milliseconds: 100), cancel.cancel);
        },
      );
      await expectLater(
        f,
        throwsA(
          isA<OAuth2Error>().having((e) => e.message, 'm', contains('cancel')),
        ),
      );
      await expectLater(
        HttpClient().getUrl(redirect!).then((r) => r.close()),
        throwsA(isA<SocketException>()),
      );
    });

    test('refresh grant sends the refresh token and keeps it', () async {
      final forms = <Map<String, String>>[];
      final ts = await tokenServer(forms, body: '{"access_token":"NEW"}');
      final t = await refreshOAuth2Token(
        HttpEngine(),
        OAuth2Auth(
          grant: OAuth2Grant.authorizationCode,
          authUrl: 'https://idp.test/a',
          tokenUrl: 'http://127.0.0.1:${ts.port}/t',
          clientId: 'c',
        ),
        'RT-old',
      );
      expect(forms.single['grant_type'], 'refresh_token');
      expect(forms.single['refresh_token'], 'RT-old');
      expect(t.accessToken, 'NEW');
      expect(t.refreshToken, 'RT-old');
    });

    test('an expired token with a refresh token stays in the cache', () {
      final cache = OAuth2TokenCache();
      const auth = OAuth2Auth(
        grant: OAuth2Grant.authorizationCode,
        authUrl: 'a',
        tokenUrl: 't',
      );
      final now = DateTime(2025);
      cache.put(
        auth,
        OAuth2Token(
          accessToken: 'a',
          refreshToken: 'r',
          expiresAt: now.subtract(const Duration(minutes: 1)),
        ),
      );
      expect(cache.get(auth, now: now), isNull);
      expect(cache.peek(auth)?.refreshToken, 'r');
      expect(cache.entries.length, 1);
      cache.remove(cache.entries.single.key);
      expect(cache.entries, isEmpty);
    });
  });
}
