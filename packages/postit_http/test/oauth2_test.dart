import 'dart:convert';
import 'dart:io';

import 'package:postit_core/postit_core.dart';
import 'package:postit_http/postit_http.dart';
import 'package:test/test.dart';

void main() {
  late HttpServer server;
  late String base;
  final seen = <({String auth, String body})>[];
  var status = 200;
  var reply = '{"access_token":"tok1","token_type":"Bearer","expires_in":3600}';

  setUp(() async {
    seen.clear();
    status = 200;
    reply = '{"access_token":"tok1","token_type":"Bearer","expires_in":3600}';
    server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    base = 'http://127.0.0.1:${server.port}/token';
    server.listen((req) async {
      final body = await utf8.decoder.bind(req).join();
      seen.add((auth: req.headers.value('authorization') ?? '', body: body));
      req.response
        ..statusCode = status
        ..headers.contentType = ContentType.json
        ..write(reply);
      await req.response.close();
    });
  });
  tearDown(() => server.close(force: true));

  test('client credentials with Basic client auth', () async {
    final t = await fetchOAuth2Token(
      HttpEngine(),
      OAuth2Auth(
        grant: OAuth2Grant.clientCredentials,
        tokenUrl: base,
        clientId: 'my id',
        clientSecret: 's:3',
        scope: 'a b',
      ),
      now: DateTime(2025),
    );
    expect(t.accessToken, 'tok1');
    expect(t.expiresAt, DateTime(2025).add(const Duration(hours: 1)));
    expect(seen.single.body, 'grant_type=client_credentials&scope=a+b');
    final basic = base64Decode(seen.single.auth.substring(6));
    expect(utf8.decode(basic), 'my+id:s%3A3');
  });

  test('password grant with credentials in the body', () async {
    await fetchOAuth2Token(
      HttpEngine(),
      OAuth2Auth(
        grant: OAuth2Grant.password,
        tokenUrl: base,
        clientId: 'c',
        clientSecret: 'x',
        username: 'u',
        password: 'p',
        clientAuthInBody: true,
      ),
    );
    expect(seen.single.auth, isEmpty);
    expect(
      seen.single.body,
      'grant_type=password&username=u&password=p&client_id=c&client_secret=x',
    );
  });

  test('errors are explained', () async {
    status = 401;
    reply = '{"error":"invalid_client","error_description":"bad secret"}';
    final auth = OAuth2Auth(
      grant: OAuth2Grant.clientCredentials,
      tokenUrl: base,
    );
    await expectLater(
      fetchOAuth2Token(HttpEngine(), auth),
      throwsA(
        isA<OAuth2Error>().having(
          (e) => e.message,
          'message',
          contains('bad secret'),
        ),
      ),
    );
    status = 200;
    reply = '{"nope":1}';
    await expectLater(
      fetchOAuth2Token(HttpEngine(), auth),
      throwsA(isA<OAuth2Error>()),
    );
    await expectLater(
      fetchOAuth2Token(
        HttpEngine(),
        const OAuth2Auth(
          grant: OAuth2Grant.clientCredentials,
          tokenUrl: 'nope',
        ),
      ),
      throwsA(isA<OAuth2Error>()),
    );
  });

  test('cache reuses fresh tokens and drops expired ones', () {
    final cache = OAuth2TokenCache();
    const auth = OAuth2Auth(
      grant: OAuth2Grant.clientCredentials,
      tokenUrl: 'u',
    );
    final now = DateTime(2025);
    cache.put(
      auth,
      OAuth2Token(
        accessToken: 'a',
        expiresAt: now.add(const Duration(minutes: 5)),
      ),
    );
    expect(cache.get(auth, now: now)?.accessToken, 'a');
    expect(cache.get(auth, now: now.add(const Duration(minutes: 5))), isNull);
    expect(cache.get(auth, now: now), isNull);
  });
}
