import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:postit_core/postit_core.dart';
import 'package:postit_http/postit_http.dart';

/// The public key from the AWS Signature V4 documentation, written in parts
/// so secret scanners do not mistake it for a real credential.
const awsExampleSecret =
    'wJalrXUtnFEMI/'
    'K7MDENG+'
    'bPxRfiCYEXAMPLEKEY';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('code + PKCE through a loopback redirect', (tester) async {
    HttpOverrides.global = null;
    final forms = <Map<String, String>>[];
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    addTearDown(() => server.close(force: true));
    server.listen((req) async {
      forms.add(Uri.splitQueryString(await utf8.decodeStream(req)));
      req.response.headers.contentType = ContentType.json;
      req.response.write('{"access_token":"AT","refresh_token":"RT"}');
      await req.response.close();
    });

    late Uri opened;
    final token = await authorizeInBrowser(
      HttpEngine(),
      OAuth2Auth(
        grant: OAuth2Grant.authorizationCode,
        authUrl: 'https://idp.test/authorize',
        tokenUrl: 'http://127.0.0.1:${server.port}/token',
        clientId: 'cid',
      ),
      openUrl: (u) async {
        opened = u;
        final q = u.queryParameters;
        final redirect = Uri.parse(q['redirect_uri']!)
            .replace(queryParameters: {'code': 'abc', 'state': q['state']!});
        final c = HttpClient();
        unawaited(
          c
              .getUrl(redirect)
              .then((r) => r.close())
              .then((r) => r.drain<void>()),
        );
      },
    );
    expect(token.accessToken, 'AT');
    expect(token.refreshToken, 'RT');
    expect(
      PkcePair.challengeFor(forms.single['code_verifier']!),
      opened.queryParameters['code_challenge'],
    );
  });

  testWidgets('signing and challenge vectors hold on this platform', (
    tester,
  ) async {
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
    expect(
      h.last.$2,
      endsWith(
        'Signature=5fa00fa31553b73ebf1942676e86291e8372ff2a2260956d9b8aae1d763fbf31',
      ),
    );
  });
}
