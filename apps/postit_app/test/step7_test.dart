import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:postit_app/src/app.dart';
import 'package:postit_app/src/settings_page.dart';
import 'package:postit_app/src/state/cookies.dart';
import 'package:postit_app/src/state/editor_state.dart';
import 'package:postit_app/src/state/history_actions.dart';
import 'package:postit_app/src/state/session.dart';
import 'package:postit_app/src/widgets/response_view.dart';
import 'package:postit_core/postit_core.dart';
import 'package:postit_http/postit_http.dart';
import 'package:postit_storage/postit_storage.dart';

HttpResponseRecord record(String body, List<Header> headers) {
  final bytes = Uint8List.fromList(utf8.encode(body));
  const z = Duration.zero;
  return HttpResponseRecord(
    status: 200,
    reason: 'OK',
    httpVersion: 'HTTP/1.1',
    headers: headers,
    body: bytes,
    wireBodySize: bytes.length,
    timings: const Timings(
      dns: z,
      connect: z,
      tls: z,
      ttfb: z,
      download: z,
      total: z,
    ),
    finalUrl: Uri.parse('http://x.test'),
    sent: SentRequest(
      head: 'h',
      body: Uint8List(0),
      url: Uri.parse('http://x.test'),
    ),
  );
}

void main() {
  test('Set-Cookie parsing and match counting', () {
    final c = parseSetCookie('sid=abc=1; Path=/; HttpOnly; Max-Age=60')!;
    expect(c.name, 'sid');
    expect(c.value, 'abc=1');
    expect(c.attributes, {'path': '/', 'httponly': '', 'max-age': '60'});
    expect(parseSetCookie('garbage'), isNull);
    expect(countMatches('aAa', 'a'), 3);
    expect(countMatches('abc', ''), 0);
  });

  testWidgets('response view: raw toggle, search count, cookies', (
    tester,
  ) async {
    final state = EditorState(
      item: const HttpRequestItem(id: 'x', name: 'x'),
      response: record('{"a":"foo","b":"foo"}', [
        ('Content-Type', 'application/json'),
        ('Set-Cookie', 'sid=1; Path=/'),
      ]),
    );
    tester.view.physicalSize = const Size(900, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(body: ResponseView(state: state)),
      ),
    );
    expect(
      find.textContaining('"a": "foo"', findRichText: true),
      findsOneWidget,
    );
    await tester.tap(find.text('Raw'));
    await tester.pump();
    expect(
      find.textContaining('{"a":"foo"', findRichText: true),
      findsOneWidget,
    );
    await tester.enterText(find.byKey(const Key('response-search')), 'foo');
    await tester.pump();
    expect(find.text('2'), findsOneWidget);
    expect(find.text('Cookies (1)'), findsOneWidget);
    await tester.tap(find.text('Cookies (1)'));
    await tester.pumpAndSettle();
    expect(find.text('sid = 1'), findsOneWidget);
  });

  test('history entry becomes a saved request', () {
    final s = WorkspaceSession.memory();
    addTearDown(s.close);
    final entry = HistoryEntry(
      id: 'H',
      workspaceId: 'w',
      method: 'POST',
      url: 'http://a.test/x?q=1',
      sentAt: DateTime(2025),
      requestJson: jsonEncode({
        'method': 'POST',
        'url': 'http://a.test/x?q=1',
        'headers': [
          ['Content-Type', 'application/json'],
          ['Authorization', Masker.placeholder],
        ],
        'body': '{"a":1}',
      }),
    );
    final parsed = requestFromHistory(entry);
    expect(parsed.hadMasked, isTrue);
    expect(parsed.item.params.single.key, 'q');
    expect((parsed.item.body as RawBody).language, RawBodyLanguage.json);
    final id = saveHistoryAsRequest(s, entry);
    expect(s.repo.getRequest(id).method, 'POST');
    expect(requestStillExists(s, entry), isFalse);
  });

  testWidgets('theme choice is saved and applied', (tester) async {
    final s = WorkspaceSession.memory();
    addTearDown(s.close);
    tester.view.physicalSize = const Size(1000, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [sessionProvider.overrideWithValue(s)],
        child: const PostItApp(),
      ),
    );
    await tester.tap(find.text('Settings'));
    await tester.pump();
    expect(find.byType(SettingsPage), findsOneWidget);
    await tester.tap(find.text('Dark'));
    await tester.pump();
    expect(s.repo.settings['themeMode'], 'dark');
    final app = tester.widget<MaterialApp>(find.byType(MaterialApp));
    expect(app.themeMode, ThemeMode.dark);
  });
}
