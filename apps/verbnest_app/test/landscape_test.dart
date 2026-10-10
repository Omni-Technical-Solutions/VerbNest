import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:verbnest_app/src/layout_class.dart';
import 'package:verbnest_app/src/state/editor_state.dart';

import 'support/device_profiles.dart';
import 'support/matrix_support.dart';

const _l874 = DeviceProfile('landscape-874x402', Size(874, 402));
const _l667 = DeviceProfile('landscape-667x375', Size(667, 375));
const _tablet = DeviceProfile('tablet-1024x768', Size(1024, 768));

void main() {
  test('height classes follow Material 3', () {
    expect(HeightClass.forHeight(479), HeightClass.compact);
    expect(HeightClass.forHeight(480), HeightClass.medium);
    expect(HeightClass.forHeight(899), HeightClass.medium);
    expect(HeightClass.forHeight(900), HeightClass.expanded);
    expect(HeightClass.compact.atLeast(HeightClass.medium), isFalse);
    expect(HeightClass.expanded.atLeast(HeightClass.medium), isTrue);
  });

  group('a landscape phone is not given list and detail', () {
    testWidgets('874x402 gets the one-pane layout with a rail', (t) async {
      await launchApp(t, _l874);
      expect(find.byKey(const Key('layout-medium')), findsOneWidget);
      expect(find.byKey(const Key('layout-expanded')), findsNothing);
      expect(find.byType(NavigationRail), findsOneWidget);
      // The collection list is the page; there is no editor beside it.
      expect(find.byKey(const Key('sidebar-filter')), findsOneWidget);
      expect(find.byKey(const Key('url')), findsNothing);
    });

    testWidgets('no status bar', (t) async {
      await launchApp(t, _l874);
      expect(find.byKey(const Key('status-bar')), findsNothing);
    });

    testWidgets('the same width with a tablet height keeps list and detail', (
      t,
    ) async {
      await launchApp(t, _tablet);
      expect(find.byKey(const Key('layout-expanded')), findsOneWidget);
      expect(find.byKey(const Key('status-bar')), findsOneWidget);
    });

    testWidgets('the rail scrolls when it does not fit', (t) async {
      const tiny = DeviceProfile('tiny-700x300', Size(700, 300));
      await launchApp(t, tiny);
      expect(t.takeException(), isNull);
      expect(
        find.descendant(
          of: find.byType(NavigationRail).first,
          matching: find.text('Settings'),
        ),
        findsOneWidget,
      );
    });
  });

  group('panes sit side by side in a short window', () {
    testWidgets('667x375', (t) async {
      final a = await launchApp(t, _l667);
      await openRequest(a, _l667);
      await t.tap(find.byKey(const Key('send')));
      await t.pump(const Duration(seconds: 1));
      await t.pump(const Duration(seconds: 1));
      final request = t.getTopLeft(find.byKey(const Key('url')));
      final response = t.getTopLeft(find.byKey(const Key('response-status')));
      expect(response.dx, greaterThan(request.dx + 200));
      // The split toggle would only fight this.
      expect(find.byKey(const Key('split-orientation')), findsNothing);
      await t.pump(EditorNotifier.saveDelay);
    });

    testWidgets('and each pane is tall enough to use', (t) async {
      final a = await launchApp(t, _l667);
      await openRequest(a, _l667);
      await t.tap(find.byKey(const Key('send')));
      await t.pump(const Duration(seconds: 1));
      await t.pump(const Duration(seconds: 1));
      // The response pane starts below the URL bar and fills to the bottom.
      final status = t.getRect(find.byKey(const Key('response-status')));
      expect(status.bottom, lessThan(_l667.size.height));
      expect(_l667.size.height - status.bottom, greaterThan(120));
      await t.pump(EditorNotifier.saveDelay);
    });

    testWidgets('a tall window keeps the stacked default', (t) async {
      const tall = DeviceProfile('tablet-1100x900', Size(1100, 900));
      final a = await launchApp(t, tall);
      await openRequest(a, tall);
      await t.tap(find.byKey(const Key('send')));
      await t.pump(const Duration(seconds: 1));
      await t.pump(const Duration(seconds: 1));
      final request = t.getTopLeft(find.byKey(const Key('url')));
      final response = t.getTopLeft(find.byKey(const Key('response-status')));
      expect(response.dy, greaterThan(request.dy + 100));
      expect(find.byKey(const Key('split-orientation')), findsOneWidget);
      await t.pump(EditorNotifier.saveDelay);
    });
  });

  group('the toolbar moves into the URL row of a short window', () {
    testWidgets('environment and menu sit beside Send; no toolbar row', (
      t,
    ) async {
      final a = await launchApp(t, _l667);
      await openRequest(a, _l667);
      expect(find.byKey(const Key('favourite')), findsNothing);
      expect(find.byKey(const Key('examples')), findsNothing);
      expect(find.byKey(const Key('toolbar-more')), findsOneWidget);
      expect(find.byKey(const Key('env-select')), findsOneWidget);
      final url = t.getRect(find.byKey(const Key('url')));
      final more = t.getRect(find.byKey(const Key('toolbar-more')));
      final env = t.getRect(find.byKey(const Key('env-select')));
      // Same row as the URL field.
      expect((more.center.dy - url.center.dy).abs(), lessThan(30));
      expect((env.center.dy - url.center.dy).abs(), lessThan(30));
      await t.pump(EditorNotifier.saveDelay);
    });

    testWidgets('the menu still reaches favourite and examples', (t) async {
      final a = await launchApp(t, _l667);
      await openRequest(a, _l667);
      await t.tap(find.byKey(const Key('toolbar-more')));
      await t.pumpAndSettle();
      expect(find.byKey(const Key('more-favourite')), findsOneWidget);
      expect(find.byKey(const Key('more-examples')), findsOneWidget);
      await t.tap(find.byKey(const Key('more-examples')));
      await t.pumpAndSettle();
      expect(find.byKey(const Key('no-examples')), findsOneWidget);
      await t.pump(EditorNotifier.saveDelay);
    });
  });

  group('display cutouts', () {
    testWidgets('content stays clear of a notch on both sides', (t) async {
      t.view.padding = const FakeViewPadding(left: 44, right: 44);
      addTearDown(t.view.resetPadding);
      final a = await launchApp(t, _l667);
      await openRequest(a, _l667);
      final url = t.getRect(find.byKey(const Key('url')));
      expect(url.left, greaterThanOrEqualTo(44));
      expect(url.right, lessThanOrEqualTo(_l667.size.width - 44));
      await t.pump(EditorNotifier.saveDelay);
    });
  });
}
