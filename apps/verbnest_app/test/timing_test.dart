import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:verbnest_app/src/state/editor_state.dart';
import 'package:verbnest_app/src/widgets/response_view.dart';
import 'package:verbnest_core/verbnest_core.dart';
import 'package:verbnest_http/verbnest_http.dart';

import 'step7_test.dart' show record;

Duration ms(int n) => Duration(milliseconds: n);

void main() {
  test('timing rows list the phases that happened', () {
    final rows = timingRows(
      Timings(
        dns: ms(2),
        connect: ms(3),
        tls: ms(10),
        ttfb: ms(40),
        download: ms(5),
        total: ms(70),
      ),
    );
    expect(rows.map((r) => r.$1), [
      'DNS lookup',
      'TCP connect',
      'TLS handshake',
      'Waiting (TTFB)',
      'Download',
      'Other',
    ]);
    expect(rows.last.$2, ms(10));
  });

  test('plain HTTP has no TLS row and no tiny "Other" row', () {
    final rows = timingRows(
      Timings(
        dns: ms(1),
        connect: ms(1),
        tls: Duration.zero,
        ttfb: ms(5),
        download: ms(1),
        total: ms(8),
      ),
    );
    expect(rows.map((r) => r.$1), isNot(contains('TLS handshake')));
    expect(rows.map((r) => r.$1), isNot(contains('Other')));
  });

  test('durations read naturally', () {
    expect(formatDuration(const Duration(microseconds: 420)), '420 µs');
    expect(formatDuration(const Duration(microseconds: 12500)), '12.5 ms');
    expect(formatDuration(const Duration(milliseconds: 2500)), '2.50 s');
  });

  test('the HTTP version setting is stored and restored', () {
    const s = RequestSettings(httpVersion: '2');
    expect(RequestSettings.fromJson(s.toJson()).httpVersion, '2');
    expect(
      s.copyWith(httpVersion: null).toJson(),
      isNot(contains('httpVersion')),
    );
    expect(const RequestSettings().toJson(), isEmpty);
  });

  Future<void> show(WidgetTester tester, HttpResponseRecord r) async {
    tester.view.physicalSize = const Size(900, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ResponseView(
            state: EditorState(
              item: const HttpRequestItem(id: 'x', name: 'x'),
              response: r,
            ),
          ),
        ),
      ),
    );
  }

  testWidgets('tapping the time opens the timing breakdown', (tester) async {
    await show(tester, record('{}', [('Content-Type', 'application/json')]));
    await tester.tap(find.byKey(const Key('response-timing')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('timing-rows')), findsOneWidget);
    expect(find.text('Waiting (TTFB)'), findsOneWidget);
  });

  testWidgets('JSON body is filtered with JSONPath', (tester) async {
    await show(
      tester,
      record('{"items":[{"id":7},{"id":9}],"total":2}', [
        ('Content-Type', 'application/json'),
      ]),
    );
    await tester.enterText(
      find.byKey(const Key('response-filter')),
      r'$.items[*].id',
    );
    await tester.pump();
    expect(find.textContaining('total', findRichText: true), findsNothing);
    expect(find.textContaining('7', findRichText: true), findsWidgets);
    await tester.enterText(find.byKey(const Key('response-filter')), 'items');
    await tester.pump();
    expect(find.textContaining('JSONPath'), findsWidgets);
  });

  testWidgets('XML bodies take XPath and plain text has no filter', (
    tester,
  ) async {
    await show(
      tester,
      record('<r><a>1</a><a>2</a></r>', [('Content-Type', 'text/xml')]),
    );
    await tester.enterText(
      find.byKey(const Key('response-filter')),
      '//a/text()',
    );
    await tester.pump();
    expect(find.textContaining('<r>', findRichText: true), findsNothing);

    await show(tester, record('plain', [('Content-Type', 'text/plain')]));
    await tester.pump();
    expect(find.byKey(const Key('response-filter')), findsNothing);
  });

  testWidgets('hex view dumps the bytes', (tester) async {
    await show(tester, record('Hi', [('Content-Type', 'text/plain')]));
    await tester.tap(find.text('Hex'));
    await tester.pump();
    expect(find.textContaining('48 69', findRichText: true), findsOneWidget);
  });
}
