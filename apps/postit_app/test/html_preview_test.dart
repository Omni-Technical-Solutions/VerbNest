import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:postit_app/src/state/editor_state.dart';
import 'package:postit_app/src/widgets/html_preview.dart';
import 'package:postit_app/src/widgets/response_view.dart';
import 'package:postit_core/postit_core.dart';
import 'package:postit_http/postit_http.dart';

import 'step7_test.dart' show record;

HttpResponseRecord _html(String body, {String type = 'text/html'}) =>
    HttpResponseRecord(
      status: 200,
      reason: 'OK',
      httpVersion: '1.1',
      headers: [('Content-Type', '$type; charset=utf-8')],
      body: Uint8List.fromList(utf8.encode(body)),
      wireBodySize: body.length,
      timings: record('', []).timings,
      finalUrl: Uri.parse('http://x.test'),
      sent: record('', []).sent,
    );

Widget _app(HttpResponseRecord r) => MaterialApp(
  home: Scaffold(
    body: ResponseView(
      state: EditorState(
        item: const HttpRequestItem(id: 'x', name: 'x'),
        response: r,
      ),
    ),
  ),
);

void main() {
  testWidgets('HTML responses offer a preview that shows the text only', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(900, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final r = _html(
      '<h1>Hello page</h1><script>throw 1</script>'
      '<p>Body <a href="http://evil.test">link</a></p>'
      '<img src="http://evil.test/x.png">',
    );
    expect(isHtmlResponse(r), isTrue);
    await tester.pumpWidget(_app(r));
    await tester.tap(find.text('Preview'));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('html-preview')), findsOneWidget);
    expect(
      find.textContaining('Hello page', findRichText: true),
      findsOneWidget,
    );
    expect(find.textContaining('throw 1', findRichText: true), findsNothing);
  });

  testWidgets('JSON responses have no preview segment', (tester) async {
    tester.view.physicalSize = const Size(900, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(_app(_html('{}', type: 'application/json')));
    expect(find.text('Preview'), findsNothing);
  });

  testWidgets('a page above the cap is not rendered', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: HtmlPreview(html: '<p>x</p>', size: maxHtmlPreviewBytes + 1),
        ),
      ),
    );
    expect(find.byKey(const Key('html-too-large')), findsOneWidget);
    expect(find.byKey(const Key('html-preview')), findsNothing);
  });
}
