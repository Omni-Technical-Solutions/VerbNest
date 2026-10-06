import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:verbnest_app/src/state/editor_state.dart';
import 'package:verbnest_app/src/widgets/pdf_preview.dart';
import 'package:verbnest_app/src/widgets/response_view.dart';
import 'package:verbnest_core/verbnest_core.dart';
import 'package:verbnest_http/verbnest_http.dart';

import 'step7_test.dart' show record;

HttpResponseRecord _pdf(int size, {String type = 'application/pdf'}) =>
    HttpResponseRecord(
      status: 200,
      reason: 'OK',
      httpVersion: '1.1',
      headers: [('Content-Type', type)],
      body: Uint8List(size),
      wireBodySize: size,
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
  test('only application/pdf counts as a PDF', () {
    expect(isPdfResponse(_pdf(1)), isTrue);
    expect(isPdfResponse(_pdf(1, type: 'Application/PDF; x=1')), isTrue);
    expect(isPdfResponse(_pdf(1, type: 'text/plain')), isFalse);
  });

  testWidgets('a PDF offers Preview; a huge one is not opened', (tester) async {
    tester.view.physicalSize = const Size(900, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(_app(_pdf(maxPdfPreviewBytes + 1)));
    await tester.tap(find.text('Preview'));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('pdf-too-large')), findsOneWidget);
    expect(find.byKey(const Key('pdf-preview')), findsNothing);
  });

  testWidgets('non-PDF responses have no Preview segment', (tester) async {
    await tester.pumpWidget(_app(_pdf(10, type: 'text/plain')));
    expect(find.text('Preview'), findsNothing);
  });
}
