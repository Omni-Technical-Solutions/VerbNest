import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:verbnest_app/src/widgets/ui/scroll_if_short.dart';

Widget _host(double height, {double scale = 1, double minHeight = 200}) =>
    MaterialApp(
      home: MediaQuery(
        data: MediaQueryData(textScaler: TextScaler.linear(scale)),
        child: Scaffold(
          body: SizedBox(
            height: height,
            child: ScrollIfShort(
              minHeight: minHeight,
              child: const Column(
                children: [
                  Text('top'),
                  Expanded(child: ColoredBox(color: Color(0xFF000000))),
                ],
              ),
            ),
          ),
        ),
      ),
    );

/// How far the form can scroll: 0 when it fits.
double _extent(WidgetTester t) =>
    t.state<ScrollableState>(find.byType(Scrollable)).position.maxScrollExtent;

void main() {
  testWidgets('with enough room it does not scroll', (t) async {
    await t.pumpWidget(_host(400));
    expect(_extent(t), 0);
    expect(t.takeException(), isNull);
  });

  testWidgets('with too little room it scrolls instead of overflowing', (
    t,
  ) async {
    await t.pumpWidget(_host(120));
    expect(_extent(t), greaterThan(0));
    expect(t.getSize(find.byType(ColoredBox).last).height, greaterThan(100));
    expect(t.takeException(), isNull);
  });

  testWidgets('the room needed grows with the text size', (t) async {
    // 300 dp is enough at 100% text but not at 200%.
    await t.pumpWidget(_host(300));
    expect(_extent(t), 0);
    await t.pumpWidget(_host(300, scale: 2));
    expect(_extent(t), greaterThan(0));
    expect(t.takeException(), isNull);
  });

  testWidgets('a smaller than normal text size does not shrink the minimum', (
    t,
  ) async {
    await t.pumpWidget(_host(150, scale: 0.8));
    expect(_extent(t), greaterThan(0));
  });

  testWidgets('the keyboard taking room does not rebuild the form', (t) async {
    var height = 700.0;
    late StateSetter update;
    await t.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: StatefulBuilder(
            builder: (c, s) {
              update = s;
              return SizedBox(
                height: height,
                child: const ScrollIfShort(
                  minHeight: 420,
                  child: Column(
                    children: [
                      TextField(key: Key('f')),
                      Expanded(child: SizedBox()),
                    ],
                  ),
                ),
              );
            },
          ),
        ),
      ),
    );
    final field = find.descendant(
      of: find.byKey(const Key('f')),
      matching: find.byType(EditableText),
    );
    await t.tap(field);
    await t.pump();
    final before = t.state<EditableTextState>(field);
    expect(before.widget.focusNode.hasFocus, isTrue);
    // The keyboard opens: less room than the form needs, then room again.
    for (final h in [300.0, 700.0, 250.0]) {
      update(() => height = h);
      await t.pump();
      expect(identical(t.state<EditableTextState>(field), before), isTrue);
      expect(before.widget.focusNode.hasFocus, isTrue);
    }
  });

  testWidgets('a short area scrolls and a tall one does not', (t) async {
    Future<void> pumpAt(double h) => t.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SizedBox(
            height: h,
            child: const ScrollIfShort(
              minHeight: 420,
              child: Column(children: [Expanded(child: SizedBox())]),
            ),
          ),
        ),
      ),
    );
    await pumpAt(300);
    expect(
      t
          .state<ScrollableState>(find.byType(Scrollable))
          .position
          .maxScrollExtent,
      120,
    );
    await pumpAt(700);
    expect(
      t
          .state<ScrollableState>(find.byType(Scrollable))
          .position
          .maxScrollExtent,
      0,
    );
  });
}
