import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:verbnest_app/src/widgets/ui/still_scrollbar.dart';
import 'package:verbnest_app/src/state/editor_state.dart';
import 'package:verbnest_app/src/widgets/code_view.dart';
import 'package:verbnest_app/src/widgets/ui/scroll_edge_fade.dart';

import 'support/device_profiles.dart';
import 'support/golden_setup.dart';
import 'support/matrix_support.dart';

Widget _row({TextDirection dir = TextDirection.ltr, double itemWidth = 200}) =>
    Directionality(
      textDirection: dir,
      child: Center(
        child: SizedBox(
          width: 300,
          height: 48,
          child: ScrollEdgeFade(
            child: SingleChildScrollView(
              key: const Key('row'),
              scrollDirection: Axis.horizontal,
              child: Row(
                children: [
                  for (var i = 0; i < 3; i++)
                    SizedBox(width: itemWidth, child: Text('item $i')),
                ],
              ),
            ),
          ),
        ),
      ),
    );

Future<void> _pump(WidgetTester t, Widget w) async {
  await t.pumpWidget(MaterialApp(home: Scaffold(body: w)));
  await t.pump();
  await t.pump(const Duration(milliseconds: 50));
}

void main() {
  // Real text widths: the default test font is far wider than the app's.
  setUpAll(loadGoldenFonts);

  group('ScrollEdgeFade', () {
    testWidgets('shows a fade only on the side with hidden content', (t) async {
      await _pump(t, _row());
      expect(find.byKey(const Key('fade-end')), findsOneWidget);
      expect(find.byKey(const Key('fade-start')), findsNothing);

      t.state<ScrollableState>(find.byType(Scrollable)).position.jumpTo(100);
      await t.pump();
      expect(find.byKey(const Key('fade-start')), findsOneWidget);
      expect(find.byKey(const Key('fade-end')), findsOneWidget);

      t.state<ScrollableState>(find.byType(Scrollable)).position.jumpTo(10000);
      await t.pump();
      expect(find.byKey(const Key('fade-start')), findsOneWidget);
      expect(find.byKey(const Key('fade-end')), findsNothing);
    });

    testWidgets('shows nothing when everything fits', (t) async {
      await _pump(t, _row(itemWidth: 80));
      expect(find.byKey(const Key('fade-start')), findsNothing);
      expect(find.byKey(const Key('fade-end')), findsNothing);
    });

    testWidgets('flips in right-to-left', (t) async {
      await _pump(t, _row(dir: TextDirection.rtl));
      // The content starts at the right; what is hidden is to the left.
      final fade = t.getRect(find.byKey(const Key('fade-end')));
      final box = t.getRect(find.byKey(const Key('row')));
      expect(fade.left, closeTo(box.left, 1));
    });

    testWidgets('does not take touches or reach screen readers', (t) async {
      await _pump(t, _row());
      final fade = find.byKey(const Key('fade-end'));
      expect(
        find.descendant(of: fade, matching: find.byType(IgnorePointer)),
        findsOneWidget,
      );
      expect(
        find.descendant(of: fade, matching: find.byType(ExcludeSemantics)),
        findsOneWidget,
      );
    });
  });

  group('the real tab bars', () {
    const se = DeviceProfile('se-320x568', Size(320, 568));
    const wide = DeviceProfile('desktop-1280x800', Size(1280, 800));

    testWidgets('request tabs fade at 320 and not when they all fit', (
      t,
    ) async {
      final a = await launchApp(t, se);
      await openRequest(a, se);
      expect(find.byKey(const Key('fade-end')), findsWidgets);
      await t.pump(EditorNotifier.saveDelay);
    });

    testWidgets('and not on a wide window', (t) async {
      final a = await launchApp(t, wide);
      await openRequest(a, wide);
      expect(find.byKey(const Key('fade-end')), findsNothing);
      expect(find.byKey(const Key('fade-start')), findsNothing);
      await t.pump(EditorNotifier.saveDelay);
    });
  });

  group('the code view', () {
    testWidgets('has a visible scrollbar when a line runs past the edge', (
      t,
    ) async {
      t.view.physicalSize = const Size(320, 400);
      t.view.devicePixelRatio = 1;
      addTearDown(t.view.reset);
      await t.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: CodeView(text: '{"a": "${'x' * 200}"}', fontSize: 13),
          ),
        ),
      );
      await t.pump();
      final bar = t.widget<StillScrollbar>(find.byType(StillScrollbar).first);
      expect(bar.thumbVisibility, isTrue);
    });

    testWidgets('and none when everything fits', (t) async {
      await t.pumpWidget(
        const MaterialApp(
          home: Scaffold(body: CodeView(text: '{"a": 1}', fontSize: 13)),
        ),
      );
      await t.pump();
      final bar = t.widget<StillScrollbar>(find.byType(StillScrollbar).first);
      expect(bar.thumbVisibility, isFalse);
    });
  });

  group('key/value tables', () {
    Future<void> openParams(WidgetTester t, DeviceProfile p) async {
      final a = await launchApp(t, p);
      await openRequest(a, p);
      await t.pump(const Duration(milliseconds: 300));
    }

    testWidgets('stack the value under the key under 360 dp', (t) async {
      const se = DeviceProfile('se-320x568', Size(320, 568));
      await openParams(t, se);
      final key = t.getRect(find.byKey(const ValueKey('params-key-0')));
      final value = t.getRect(find.byKey(const ValueKey('params-value-0')));
      expect(value.top, greaterThan(key.bottom - 4));
      // And the fields are wide enough to read.
      expect(key.width, greaterThan(150));
      expect(value.width, greaterThan(150));
      await t.pump(EditorNotifier.saveDelay);
    });

    testWidgets('stay side by side from 360 dp', (t) async {
      const phone = DeviceProfile('iphone-402x874', Size(402, 874));
      await openParams(t, phone);
      final key = t.getRect(find.byKey(const ValueKey('params-key-0')));
      final value = t.getRect(find.byKey(const ValueKey('params-value-0')));
      expect((value.center.dy - key.center.dy).abs(), lessThan(8));
      expect(value.left, greaterThan(key.right));
      await t.pump(EditorNotifier.saveDelay);
    });
  });
}
