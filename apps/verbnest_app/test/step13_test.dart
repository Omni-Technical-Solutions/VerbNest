import 'dart:convert';

import 'package:material_ui/material_ui.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:verbnest_app/src/state/code_view.dart';
import 'package:verbnest_app/src/state/editor_state.dart';
import 'package:verbnest_app/src/widgets/code_view.dart';
import 'package:verbnest_app/src/widgets/response_view.dart';
import 'package:verbnest_core/verbnest_core.dart';
import 'package:verbnest_http/verbnest_http.dart';

import 'step7_test.dart' show record;

void main() {
  group('code_view helpers', () {
    test('tokenizes keys, strings, numbers and literals', () {
      const line = '  "a": "x", "n": -1.5e3, "t": true, "z": null';
      final kinds = tokenizeJsonLine(line).map((t) => t.kind).toList();
      expect(kinds.where((k) => k == TokenKind.key).length, 4);
      expect(kinds, contains(TokenKind.string));
      expect(kinds, contains(TokenKind.number));
      expect(kinds.where((k) => k == TokenKind.literal).length, 2);
    });

    test('fold ranges match brackets and collapse hides the body', () {
      final lines = splitLines(
        const JsonEncoder.withIndent('  ').convert({
          'a': [1, 2],
          'b': {'c': 1},
        }),
      );
      final folds = foldRanges(lines);
      expect(folds[0], lines.length - 1);
      final arrayStart = lines.indexWhere((l) => l.trimRight().endsWith('['));
      expect(lines[folds[arrayStart]!].trim(), startsWith(']'));
      final visible = visibleLines(lines.length, folds, {arrayStart});
      expect(visible.length, lines.length - 2);
      expect(visible, contains(folds[arrayStart]));
    });

    test('a 5 MB JSON body is pretty-printed and indexed quickly', () {
      final big = jsonEncode({
        'items': [
          for (var i = 0; i < 85000; i++)
            {
              'id': i,
              'name': 'item-$i',
              'tags': ['a', 'b'],
              'ok': i.isEven,
            },
        ],
      });
      expect(big.length, greaterThan(4 * 1024 * 1024));
      final sw = Stopwatch()..start();
      final pretty = const JsonEncoder.withIndent('  ')
          .convert(jsonDecode(big));
      final lines = splitLines(pretty);
      final folds = foldRanges(lines);
      sw.stop();
      expect(lines.length, greaterThan(500000));
      expect(folds.length, greaterThan(100000));
      // Generous bound: this guards against accidental quadratic work.
      expect(sw.elapsedMilliseconds, lessThan(8000));
    });
  });

  testWidgets('code view shows line numbers and folds a block', (tester) async {
    tester.view.physicalSize = const Size(800, 600);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    const text = '{\n  "a": [\n    1\n  ]\n}';
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(body: CodeView(text: text, json: true)),
      ),
    );
    expect(find.text('5'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('fold-1')));
    await tester.pump();
    expect(find.text('3'), findsNothing);
    expect(find.text('4'), findsOneWidget);
  });

  testWidgets('image responses offer a preview; sizes show wire size', (
    tester,
  ) async {
    // 1x1 transparent PNG.
    final png = base64Decode(
      'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mNkYPhfDwAChwGA60e6kgAAAABJRU5ErkJggg==',
    );
    final r = HttpResponseRecord(
      status: 200,
      reason: 'OK',
      httpVersion: 'HTTP/1.1',
      headers: [('Content-Type', 'image/png'), ('X-Id', 'abc')],
      body: Uint8List.fromList(png),
      wireBodySize: 10,
      timings: record('', []).timings,
      finalUrl: Uri.parse('http://x.test'),
      sent: record('', []).sent,
    );
    expect(isImageResponse(r), isTrue);
    expect(sizeLabel(r), contains('on the wire'));
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
    await tester.tap(find.text('Preview'));
    await tester.pump();
    expect(find.byKey(const Key('response-image')), findsOneWidget);

    String? copied;
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      SystemChannels.platform,
      (call) async {
        if (call.method == 'Clipboard.setData') {
          copied = (call.arguments as Map)['text'] as String?;
        }
        return null;
      },
    );
    await tester.tap(find.text('Headers'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('copy-header-1')));
    await tester.pump();
    expect(copied, 'abc');
  });
}
