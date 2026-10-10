import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:material_ui/material_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:verbnest_app/src/state/browser_port.dart';
import 'package:verbnest_app/src/state/editor_state.dart';
import 'package:verbnest_app/src/state/session.dart';
import 'package:verbnest_app/src/widgets/auth_editor.dart';
import 'package:verbnest_app/src/widgets/token_manager.dart';
import 'package:verbnest_core/verbnest_core.dart';
import 'package:verbnest_http/verbnest_http.dart';

class ScriptedEngine extends HttpEngine {
  ScriptedEngine(this.handler);

  final (int, List<Header>, String) Function(HttpRequestSpec) handler;
  final sent = <HttpRequestSpec>[];

  @override
  Future<HttpResponseRecord> send(
    HttpRequestSpec spec, {
    CancelToken? cancel,
  }) async {
    sent.add(spec);
    final (status, headers, text) = handler(spec);
    final body = Uint8List.fromList(utf8.encode(text));
    const zero = Duration.zero;
    return HttpResponseRecord(
      status: status,
      reason: status == 200 ? 'OK' : 'Other',
      httpVersion: '1.1',
      headers: headers,
      body: body,
      wireBodySize: body.length,
      timings: const Timings(
        dns: zero,
        connect: zero,
        tls: zero,
        ttfb: zero,
        download: zero,
        total: Duration(milliseconds: 3),
      ),
      finalUrl: spec.url,
      sent: SentRequest(head: 'x\r\n\r\n', body: Uint8List(0), url: spec.url),
    );
  }
}

Future<void> hit(Uri u) async {
  final c = HttpClient();
  final r = await (await c.getUrl(u)).close();
  await r.drain<void>();
  c.close();
}

({ProviderContainer c, WorkspaceSession s, ScriptedEngine e, List<Uri> opened})
setup(
  (int, List<Header>, String) Function(HttpRequestSpec) handler,
  Future<void> Function(Uri)? opener,
) {
  final s = WorkspaceSession.memory();
  final e = ScriptedEngine(handler);
  final opened = <Uri>[];
  final c = ProviderContainer(
    overrides: [
      sessionProvider.overrideWithValue(s),
      engineProvider.overrideWithValue(e),
      browserOpenerProvider.overrideWithValue((u) async {
        opened.add(u);
        await opener?.call(u);
      }),
    ],
  );
  addTearDown(() {
    c.dispose();
    s.close();
  });
  return (c: c, s: s, e: e, opened: opened);
}

String newRequest(
  WorkspaceSession s,
  Auth auth, {
  String url = 'http://x.test/a',
}) {
  final col = s.repo.createCollection('C');
  return s.repo.createRequest(
    col,
    HttpRequestItem(id: '', name: 'R', url: url, auth: auth),
  );
}

void main() {
  // flutter_test replaces HttpClient with one that always answers 400; the
  // loopback sign-in tests need real sockets.
  setUpAll(() => HttpOverrides.global = null);

  const tokenJson =
      '{"access_token":"AT1","refresh_token":"RT1","expires_in":3600}';

  group('OAuth 2.0 in the send flow', () {
    test('code grant signs in once, then reuses the token', () async {
      final t = setup(
        (spec) => spec.url.path == '/token'
            ? (200, [('Content-Type', 'application/json')], tokenJson)
            : (200, <Header>[], 'ok'),
        (u) async {
          final q = u.queryParameters;
          unawaited2(
            hit(
              Uri.parse(
                q['redirect_uri']!,
              ).replace(queryParameters: {'code': 'c', 'state': q['state']!}),
            ),
          );
        },
      );
      final id = newRequest(
        t.s,
        const OAuth2Auth(
          grant: OAuth2Grant.authorizationCode,
          authUrl: 'https://idp.test/authorize',
          tokenUrl: 'http://idp.test/token',
          clientId: 'cid',
        ),
      );
      final n = t.c.read(editorProvider(id).notifier);
      await n.send();
      expect(t.c.read(editorProvider(id)).error, isNull);
      expect(t.opened.length, 1);
      final api = t.e.sent.last;
      expect(
        api.headers.firstWhere((h) => h.$1 == 'Authorization').$2,
        'Bearer AT1',
      );

      await n.send();
      expect(t.opened.length, 1, reason: 'cached token is reused');
      expect(
        t.c.read(oauthCacheProvider).entries.single.token.refreshToken,
        'RT1',
      );
    });

    test('an expired token is refreshed without opening the browser', () async {
      final forms = <Map<String, String>>[];
      final t = setup((spec) {
        if (spec.url.path == '/token') {
          forms.add(Uri.splitQueryString(utf8.decode(spec.body!)));
          return (200, <Header>[], '{"access_token":"AT2","expires_in":60}');
        }
        return (200, <Header>[], 'ok');
      }, null);
      const auth = OAuth2Auth(
        grant: OAuth2Grant.authorizationCode,
        authUrl: 'https://idp.test/authorize',
        tokenUrl: 'http://idp.test/token',
        clientId: 'cid',
      );
      t.c
          .read(oauthCacheProvider)
          .put(
            auth,
            OAuth2Token(
              accessToken: 'old',
              refreshToken: 'RT-old',
              expiresAt: DateTime.now().subtract(const Duration(hours: 1)),
            ),
          );
      final id = newRequest(t.s, auth);
      await t.c.read(editorProvider(id).notifier).send();
      expect(t.opened, isEmpty);
      expect(forms.single['grant_type'], 'refresh_token');
      expect(forms.single['refresh_token'], 'RT-old');
      expect(
        t.e.sent.last.headers.firstWhere((h) => h.$1 == 'Authorization').$2,
        'Bearer AT2',
      );
    });

    test('a refused refresh token falls back to the browser', () async {
      final t = setup(
        (spec) {
          if (spec.url.path == '/token') {
            final form = Uri.splitQueryString(utf8.decode(spec.body!));
            return form['grant_type'] == 'refresh_token'
                ? (400, <Header>[], '{"error":"invalid_grant"}')
                : (200, <Header>[], tokenJson);
          }
          return (200, <Header>[], 'ok');
        },
        (u) async {
          final q = u.queryParameters;
          unawaited2(
            hit(
              Uri.parse(
                q['redirect_uri']!,
              ).replace(queryParameters: {'code': 'c', 'state': q['state']!}),
            ),
          );
        },
      );
      const auth = OAuth2Auth(
        grant: OAuth2Grant.authorizationCode,
        authUrl: 'https://idp.test/authorize',
        tokenUrl: 'http://idp.test/token',
        clientId: 'cid',
      );
      t.c
          .read(oauthCacheProvider)
          .put(
            auth,
            OAuth2Token(
              accessToken: 'old',
              refreshToken: 'dead',
              expiresAt: DateTime.now().subtract(const Duration(hours: 1)),
            ),
          );
      final id = newRequest(t.s, auth);
      await t.c.read(editorProvider(id).notifier).send();
      expect(t.opened.length, 1);
      expect(t.c.read(editorProvider(id)).error, isNull);
    });

    test('a browser that cannot open is reported, not thrown', () async {
      final t = setup((_) => (200, <Header>[], 'ok'), (_) async {
        throw StateError('no browser');
      });
      final id = newRequest(
        t.s,
        const OAuth2Auth(
          grant: OAuth2Grant.implicit,
          authUrl: 'https://idp.test/authorize',
          clientId: 'c',
        ),
      );
      await t.c.read(editorProvider(id).notifier).send();
      expect(t.c.read(editorProvider(id)).error, contains('browser'));
      expect(t.c.read(editorProvider(id)).sending, isFalse);
    });
  });

  group('other auth in the send flow', () {
    test('Digest answers the challenge', () async {
      final t = setup((spec) {
        final has = spec.headers.any((h) => h.$1 == 'Authorization');
        return has
            ? (200, <Header>[], 'in')
            : (
                401,
                <Header>[
                  (
                    'WWW-Authenticate',
                    'Digest realm="r", qop="auth", nonce="n"',
                  ),
                ],
                '',
              );
      }, null);
      final id = newRequest(
        t.s,
        const DigestAuth(username: 'u', password: 'p'),
      );
      await t.c.read(editorProvider(id).notifier).send();
      expect(t.e.sent.length, 2);
      expect(t.c.read(editorProvider(id)).response!.status, 200);
    });

    test(
      'a signed JWT and SigV4 headers are masked in the sent view',
      () async {
        final t = setup((_) => (200, <Header>[], 'ok'), null);
        final jwt = newRequest(
          t.s,
          const JwtAuth(secret: 'sekret', payload: '{"a":1}'),
        );
        await t.c.read(editorProvider(jwt).notifier).send();
        final h = t.e.sent.last.headers.firstWhere(
          (h) => h.$1 == 'Authorization',
        );
        expect(h.$2, startsWith('Bearer eyJ'));

        final aws = newRequest(
          t.s,
          const AwsV4Auth(
            accessKey: 'AK',
            secretKey: 'SK',
            region: 'us-east-1',
            service: 'execute-api',
          ),
          url: 'https://api.test/items?b=2&a=1',
        );
        await t.c.read(editorProvider(aws).notifier).send();
        final names = t.e.sent.last.headers.map((h) => h.$1);
        expect(names, containsAll(['X-Amz-Date', 'Authorization']));
      },
    );
  });

  group('auth editor', () {
    testWidgets('new types show their fields', (tester) async {
      Auth auth = const NoAuth();
      await tester.pumpWidget(
        ProviderScope(
          child: MaterialApp(
            home: Scaffold(
              body: StatefulBuilder(
                builder: (context, set) => AuthEditor(
                  auth: auth,
                  onChanged: (a) => set(() => auth = a),
                ),
              ),
            ),
          ),
        ),
      );
      Future<void> choose(String type) async {
        await tester.tap(find.byKey(const Key('auth-type')));
        await tester.pumpAndSettle();
        await tester.tap(find.text(type).last);
        await tester.pumpAndSettle();
      }

      await choose('digest');
      expect(auth, isA<DigestAuth>());
      expect(find.byKey(const Key('auth-Username')), findsOneWidget);

      await choose('jwt');
      expect(find.byKey(const Key('jwt-algorithm')), findsOneWidget);

      await choose('awsv4');
      expect(find.byKey(const Key('auth-Region')), findsOneWidget);

      await choose('oauth2');
      await tester.tap(find.byKey(const Key('oauth-grant')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Authorization code (browser)').last);
      await tester.pumpAndSettle();
      expect((auth as OAuth2Auth).grant, OAuth2Grant.authorizationCode);
      expect(find.byKey(const Key('oauth-Auth URL')), findsOneWidget);
      expect(find.byKey(const Key('oauth-pkce')), findsOneWidget);

      await tester.tap(find.byKey(const Key('oauth-grant')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Implicit (browser)').last);
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('oauth-Token URL')), findsNothing);
      expect(find.byKey(const Key('oauth-pkce')), findsNothing);
    });

    testWidgets('token manager lists and deletes tokens', (tester) async {
      final cache = OAuth2TokenCache();
      cache.put(
        const OAuth2Auth(
          grant: OAuth2Grant.authorizationCode,
          authUrl: 'https://a',
          tokenUrl: 'https://idp.test/token',
          clientId: 'client-1',
        ),
        const OAuth2Token(accessToken: 'secret-token', refreshToken: 'r'),
      );
      await tester.pumpWidget(
        ProviderScope(
          overrides: [oauthCacheProvider.overrideWithValue(cache)],
          child: MaterialApp(
            home: Builder(
              builder: (context) => TextButton(
                onPressed: () => showTokenManager(context),
                child: const Text('open'),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();
      expect(find.textContaining('client-1'), findsOneWidget);
      expect(find.textContaining('has refresh token'), findsOneWidget);
      expect(find.textContaining('secret-token'), findsNothing);

      await tester.tap(find.byKey(const Key('tokens-clear')));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('tokens-empty')), findsOneWidget);
      expect(cache.entries, isEmpty);
    });
  });
}

void unawaited2(Future<void> f) {
  f.ignore();
}
