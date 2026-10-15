import 'package:flutter/gestures.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:verbnest_app/src/widgets/code_view.dart';

import 'support/device_profiles.dart';
import 'support/matrix_support.dart';

/// Scrolling a response must only move the content. With a mouse wheel the
/// pointer stays still while rows pass under it; those rows must not swap their
/// line number for the copy-path icon or rebuild the list.
void main() {
  final json =
      '[\n${List.generate(600, (i) => '  {"id": $i},').join('\n')}\n  {}\n]';
  const origin = Offset(200, 100);

  Future<TestGesture> mouse(WidgetTester t) async {
    final g = await t.createGesture(kind: PointerDeviceKind.mouse);
    await g.addPointer(location: const Offset(10, 10));
    addTearDown(g.removePointer);
    return g;
  }

  Finder copyIcons() => find.byWidgetPredicate(
    (w) =>
        w.key is ValueKey &&
        '${(w.key as ValueKey).value}'.startsWith('copy-path-'),
  );

  Future<void> pumpView(WidgetTester t) => t.pumpWidget(
    MaterialApp(
      home: Scaffold(body: CodeView(text: json, json: true)),
    ),
  );

  testWidgets('hovering a row still shows copy-path', (t) async {
    await pumpView(t);
    final g = await mouse(t);
    await g.moveTo(origin);
    await t.pump();
    expect(copyIcons(), findsOneWidget);
  });

  testWidgets('wheel scrolling under a still pointer shows no copy-path', (
    t,
  ) async {
    await pumpView(t);
    final g = await mouse(t);
    await g.moveTo(origin);
    await t.pump();
    for (var i = 0; i < 5; i++) {
      await t.sendEventToBinding(
        PointerScrollEvent(
          kind: PointerDeviceKind.mouse,
          position: origin,
          scrollDelta: const Offset(0, 120),
        ),
      );
      await t.pump(const Duration(milliseconds: 16));
      // While the list moves nothing is hovered.
      expect(copyIcons(), findsNothing, reason: 'scroll step $i');
    }
    await t.pump(const Duration(milliseconds: 500));
    // Rows that arrived under a still pointer stay plain until it moves.
    expect(copyIcons(), findsNothing);
    await g.moveTo(origin + const Offset(0, 20));
    await t.pump();
    expect(copyIcons(), findsOneWidget);
  });

  testWidgets('the code view does not bounce past its ends', (t) async {
    await pumpView(t);
    final list = t.widget<ListView>(find.byKey(const Key('response-body')));
    expect(list.physics, isA<ClampingScrollPhysics>());
  });

  testWidgets('the whole app scrolls without bounce or stretch', (t) async {
    final a = await launchApp(t, const DeviceProfile('d', Size(1280, 800)));
    final behavior = ScrollConfiguration.of(
      t.element(find.byType(Scaffold).first),
    );
    expect(
      behavior.getScrollPhysics(t.element(find.byType(Scaffold).first)),
      isA<ClampingScrollPhysics>(),
    );
    expect(a.id, isNotEmpty);
  });
}
