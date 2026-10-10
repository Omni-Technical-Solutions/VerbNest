import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:verbnest_app/src/state/editor_state.dart';

import 'support/device_profiles.dart';
import 'support/matrix_support.dart';

void main() {
  const landscapeWithKeyboard = DeviceProfile(
    'landscape-740x360+keyboard',
    Size(740, 360),
    keyboard: 200,
  );

  /// The editor's page scroll view (the only CustomScrollView on screen).
  Finder editorScroll() => find.byType(CustomScrollView);

  testWidgets('a short window scrolls the page instead of overflowing', (
    t,
  ) async {
    final a = await launchApp(t, landscapeWithKeyboard);
    final errors = await collectErrors(() async {
      await openRequest(a, landscapeWithKeyboard);
      await raiseKeyboard(
        a,
        landscapeWithKeyboard,
        find.byKey(const Key('url')),
      );
      await t.tap(find.byKey(const Key('send')), warnIfMissed: false);
      await t.pump(const Duration(seconds: 1));
      await t.pump(const Duration(seconds: 1));
    });
    expect(errors, isEmpty);

    final view = t.state<ScrollableState>(
      find
          .descendant(
            of: editorScroll().first,
            matching: find.byType(Scrollable),
          )
          .first,
    );
    expect(view.position.maxScrollExtent, greaterThan(0));
    await t.pump(EditorNotifier.saveDelay);
  });

  testWidgets('scrolling brings the response into view', (t) async {
    final a = await launchApp(t, landscapeWithKeyboard);
    await collectErrors(() async {
      await openRequest(a, landscapeWithKeyboard);
      await t.tap(find.byKey(const Key('send')), warnIfMissed: false);
      await t.pump(const Duration(seconds: 1));
      await t.pump(const Duration(seconds: 1));
    });
    final status = find.byKey(const Key('response-status'));
    final before = t.getTopLeft(status).dy;
    await t.drag(editorScroll().first, const Offset(0, -150));
    await t.pump(const Duration(milliseconds: 400));
    expect(t.getTopLeft(status).dy, lessThan(before));
    await t.pump(EditorNotifier.saveDelay);
  });

  testWidgets('dragging dismisses the keyboard', (t) async {
    final a = await launchApp(t, landscapeWithKeyboard);
    await collectErrors(() => openRequest(a, landscapeWithKeyboard));
    final scroll = t.widget<CustomScrollView>(editorScroll().first);
    expect(
      scroll.keyboardDismissBehavior,
      ScrollViewKeyboardDismissBehavior.onDrag,
    );
    await t.pump(EditorNotifier.saveDelay);
  });

  testWidgets('a tall window does not scroll: the panes fill it', (t) async {
    const tall = DeviceProfile('tall-402x874', Size(402, 874));
    final a = await launchApp(t, tall);
    await collectErrors(() => openRequest(a, tall));
    final view = t.state<ScrollableState>(
      find
          .descendant(
            of: editorScroll().first,
            matching: find.byType(Scrollable),
          )
          .first,
    );
    expect(view.position.maxScrollExtent, 0);
    await t.pump(EditorNotifier.saveDelay);
  });
}
