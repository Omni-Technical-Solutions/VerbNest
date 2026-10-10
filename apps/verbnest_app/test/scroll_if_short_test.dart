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

void main() {
  testWidgets('with enough room it adds nothing', (t) async {
    await t.pumpWidget(_host(400));
    expect(find.byType(SingleChildScrollView), findsNothing);
    expect(t.takeException(), isNull);
  });

  testWidgets('with too little room it scrolls instead of overflowing', (
    t,
  ) async {
    await t.pumpWidget(_host(120));
    expect(find.byType(SingleChildScrollView), findsOneWidget);
    expect(t.getSize(find.byType(ColoredBox).last).height, greaterThan(100));
    expect(t.takeException(), isNull);
  });

  testWidgets('the room needed grows with the text size', (t) async {
    // 300 dp is enough at 100% text but not at 200%.
    await t.pumpWidget(_host(300));
    expect(find.byType(SingleChildScrollView), findsNothing);
    await t.pumpWidget(_host(300, scale: 2));
    expect(find.byType(SingleChildScrollView), findsOneWidget);
    expect(t.takeException(), isNull);
  });

  testWidgets('a smaller than normal text size does not shrink the minimum', (
    t,
  ) async {
    await t.pumpWidget(_host(150, scale: 0.8));
    expect(find.byType(SingleChildScrollView), findsOneWidget);
  });
}
