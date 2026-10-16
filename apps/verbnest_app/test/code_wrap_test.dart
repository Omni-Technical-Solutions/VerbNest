import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:verbnest_app/src/widgets/ui/still_scrollbar.dart';
import 'package:verbnest_app/src/widgets/code_view.dart';

Widget _app(String text, {required bool wrap, bool json = false}) =>
    MaterialApp(
      home: Scaffold(
        body: SizedBox(
          width: 300,
          height: 400,
          child: CodeView(text: text, wrap: wrap, json: json),
        ),
      ),
    );

void main() {
  final long = '{"note": "${'word ' * 80}"}';

  testWidgets('wrap off: a long line stays one row and scrolls sideways', (
    t,
  ) async {
    await t.pumpWidget(_app(long, wrap: false, json: true));
    final h = t.getSize(find.byType(Text).last).height;
    expect(h, lessThan(30));
    expect(find.byType(StillScrollbar), findsOneWidget);
  });

  testWidgets('wrap on: a long line takes several rows, no sideways scroll', (
    t,
  ) async {
    await t.pumpWidget(_app(long, wrap: true, json: true));
    final h = t.getSize(find.byType(Text).last).height;
    expect(h, greaterThan(60));
    final scroller = t.widget<SingleChildScrollView>(
      find.byType(SingleChildScrollView).first,
    );
    expect(scroller.scrollDirection, Axis.horizontal);
    final box = t.getSize(find.byType(SingleChildScrollView).first);
    expect(t.getSize(find.byKey(const Key('response-body'))).width, box.width);
  });

  testWidgets('folding and search still work while wrapped', (t) async {
    const text = '{\n  "a": {\n    "b": 1\n  },\n  "c": "needle"\n}';
    await t.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: CodeView(text: text, json: true, wrap: true, query: 'needle'),
        ),
      ),
    );
    expect(find.textContaining('"b"', findRichText: true), findsOneWidget);
    await t.tap(find.byKey(const ValueKey('fold-1')));
    await t.pump();
    expect(find.textContaining('"b"', findRichText: true), findsNothing);
    expect(find.textContaining('needle', findRichText: true), findsOneWidget);
  });

  test('a body over the caps keeps fixed rows', () {
    expect(CodeView.canWrap('short\nlines'), isTrue);
    expect(
      CodeView.canWrap(List.filled(CodeView.wrapMaxLines + 1, 'x').join('\n')),
      isFalse,
    );
    expect(CodeView.canWrap('x' * (CodeView.wrapMaxLineLength + 1)), isFalse);
  });

  testWidgets('over the cap, wrap is ignored and rows stay one line', (
    t,
  ) async {
    final big = List.filled(CodeView.wrapMaxLines + 1, long).join('\n');
    await t.pumpWidget(_app(big, wrap: true));
    final h = t.getSize(find.byType(Text).last).height;
    expect(h, lessThan(30));
  });

  testWidgets('a huge single line (invalid or minified JSON) renders quickly', (
    t,
  ) async {
    // 12,000 objects on one line, with a search hit in every one: this took
    // minutes when each segment scanned every token.
    final line =
        '[${List.generate(12000, (i) => '{"id":$i,"name":"row $i"}').join(',')}] oops';
    final sw = Stopwatch()..start();
    await t.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: CodeView(text: line, json: true, query: 'row'),
        ),
      ),
    );
    sw.stop();
    expect(sw.elapsedMilliseconds, lessThan(5000));
    expect(t.takeException(), isNull);
  });

  testWidgets('short lines are still coloured and search marks still show', (
    t,
  ) async {
    await t.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: CodeView(
            text: '{"a": "needle", "b": 1}',
            json: true,
            query: 'needle',
          ),
        ),
      ),
    );
    final text = t
        .widget<RichText>(
          find.byWidgetPredicate(
            (w) => w is RichText && w.text.toPlainText().contains('needle'),
          ),
        )
        .text;
    final spans = <TextSpan>[];
    void walk(InlineSpan s) {
      if (s is TextSpan) {
        spans.add(s);
        s.children?.forEach(walk);
      }
    }

    walk(text);
    // More than one colour, and a highlighted match.
    expect(spans.map((s) => s.style?.color).toSet().length, greaterThan(2));
    expect(spans.any((s) => s.style?.backgroundColor != null), isTrue);
  });
}
