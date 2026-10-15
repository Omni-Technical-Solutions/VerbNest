import 'package:flutter/foundation.dart'
    show TargetPlatform, debugDefaultTargetPlatformOverride;
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:verbnest_app/src/state/editor_state.dart';
import 'package:verbnest_app/src/state/session.dart';
import 'package:verbnest_app/src/widgets/code_view.dart';

import 'support/device_profiles.dart';
import 'support/matrix_support.dart';

const _se = DeviceProfile('se-320x568', Size(320, 568));
const _phone = DeviceProfile('iphone-402x874', Size(402, 874));
const _landscape = DeviceProfile('landscape-740x360', Size(740, 360));
const _desktop = DeviceProfile('desktop-1280x800', Size(1280, 800));

Future<MatrixApp> _sent(
  WidgetTester t,
  DeviceProfile p, {
  int items = 2,
}) async {
  final a = await launchApp(t, p, engine: FakeEngine(items: items));
  await openRequest(a, p);
  await t.tap(find.byKey(const Key('send')));
  await t.pump(const Duration(seconds: 1));
  await t.pump(const Duration(seconds: 1));
  return a;
}

Future<void> _settle(WidgetTester t) async {
  await t.pump(const Duration(milliseconds: 50));
  await t.pump(const Duration(milliseconds: 600));
}

void main() {
  group('pinned URL bar', () {
    testWidgets('stays put when the page scrolls', (t) async {
      await _sent(t, _landscape);
      final url = find.byKey(const Key('url'));
      final before = t.getTopLeft(url).dy;
      await t.drag(find.byType(CustomScrollView), const Offset(0, -120));
      await _settle(t);
      // The toolbar went up and away; the URL bar stopped under the app bar.
      expect(t.getTopLeft(url).dy, lessThanOrEqualTo(before));
      expect(t.getTopLeft(url).dy, lessThan(72));
      expect(t.getRect(url).bottom, lessThan(140));
      await t.pump(EditorNotifier.saveDelay);
    });
  });

  group('the toolbar gets out of the way on a phone', () {
    testWidgets('it folds while the keyboard is up', (t) async {
      final a = await launchApp(t, _phone);
      await openRequest(a, _phone);
      expect(find.byKey(const Key('favourite')), findsOneWidget);
      await raiseKeyboard(
        a,
        _phone.withKeyboard(),
        find.byKey(const Key('url')),
      );
      expect(find.byKey(const Key('favourite')), findsNothing);
      // The URL bar and Send are what stays.
      expect(find.byKey(const Key('url')), findsOneWidget);
      expect(find.byKey(const Key('send')), findsOneWidget);
      await t.pump(EditorNotifier.saveDelay);
    });

    testWidgets('it stays on a desktop even with the keyboard up', (t) async {
      final a = await launchApp(t, _desktop);
      await openRequest(a, _desktop);
      await raiseKeyboard(
        a,
        const DeviceProfile('kb', Size(1280, 800), keyboard: 200),
        find.byKey(const Key('url')),
      );
      expect(find.byKey(const Key('favourite')), findsOneWidget);
      await t.pump(EditorNotifier.saveDelay);
    });

    testWidgets('it folds when the response is scrolled down and returns on '
        'scrolling up', (t) async {
      await _sent(t, _se, items: 60);
      expect(find.byKey(const Key('toolbar-more')), findsOneWidget);
      final code = find.byType(CodeView);
      await t.drag(code, const Offset(0, -300));
      await _settle(t);
      expect(find.byKey(const Key('toolbar-more')), findsNothing);
      await t.drag(code, const Offset(0, 300));
      await _settle(t);
      expect(find.byKey(const Key('toolbar-more')), findsOneWidget);
      await t.pump(EditorNotifier.saveDelay);
    });
  });

  testWidgets(
    'on touch the toolbar folds when the scroll ends, not during it',
    (t) async {
      await _sent(t, _se, items: 60);
      expect(find.byKey(const Key('toolbar-more')), findsOneWidget);
      final top = t.getTopLeft(find.byType(CodeView)).dy;
      final g = await t.startGesture(t.getCenter(find.byType(CodeView)));
      for (var i = 0; i < 6; i++) {
        await g.moveBy(const Offset(0, -50));
        await t.pump(const Duration(milliseconds: 16));
      }
      await _settle(t);
      // Finger still down: nothing around the content has moved.
      expect(find.byKey(const Key('toolbar-more')), findsOneWidget);
      expect(t.getTopLeft(find.byType(CodeView)).dy, top);
      await g.up();
      await t.pumpAndSettle(const Duration(milliseconds: 100));
      expect(find.byKey(const Key('toolbar-more')), findsNothing);
      await t.pump(EditorNotifier.saveDelay);
    },
  );

  testWidgets('on a desktop the toolbar does not fold while scrolling', (
    t,
  ) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.macOS;
    try {
      // A narrow Mac window counts as compact, like a phone.
      await _sent(t, _phone, items: 60);
      expect(find.byKey(const Key('favourite')), findsOneWidget);
      final before = t.getSize(find.byKey(const Key('favourite'))).height;
      final top = t.getTopLeft(find.byType(CodeView)).dy;
      await t.drag(find.byType(CodeView), const Offset(0, -300));
      await _settle(t);
      await t.drag(find.byType(CodeView), const Offset(0, 300));
      await _settle(t);
      // Same toolbar, same pane position.
      expect(t.getSize(find.byKey(const Key('favourite'))).height, before);
      expect(t.getTopLeft(find.byType(CodeView)).dy, top);
      await t.pump(EditorNotifier.saveDelay);
    } finally {
      debugDefaultTargetPlatformOverride = null;
    }
  });

  group('narrow screens (under 360 dp)', () {
    testWidgets('the toolbar is one row with a menu for the rest', (t) async {
      final a = await launchApp(t, _se);
      await openRequest(a, _se);
      expect(find.byKey(const Key('toolbar-more')), findsOneWidget);
      expect(find.byKey(const Key('favourite')), findsNothing);
      expect(find.byKey(const Key('examples')), findsNothing);
      await t.tap(find.byKey(const Key('toolbar-more')));
      await t.pumpAndSettle(); // the menu route has to finish opening
      expect(find.byKey(const Key('more-favourite')), findsOneWidget);
      expect(find.byKey(const Key('more-examples')), findsOneWidget);

      final repo = a.c.read(repositoryProvider);
      expect(repo.isFavourite(a.id), isFalse);
      await t.tap(find.byKey(const Key('more-favourite')));
      await t.pumpAndSettle();
      expect(repo.isFavourite(a.id), isTrue);
      await t.pump(EditorNotifier.saveDelay);
    });

    testWidgets('the URL field shows about 14 characters or more', (t) async {
      final a = await launchApp(t, _se);
      await openRequest(a, _se);
      expect(t.getSize(find.byKey(const Key('url'))).width, greaterThan(130));
      await t.pump(EditorNotifier.saveDelay);
    });

    testWidgets('the protocol version is dropped from the status line', (
      t,
    ) async {
      await _sent(t, _se);
      expect(find.byKey(const Key('response-http')), findsNothing);
      expect(find.byKey(const Key('response-status')), findsOneWidget);
      await t.pump(EditorNotifier.saveDelay);
    });

    testWidgets(
      'with the toolbar folded the body gets 35% of a 320x568 screen',
      (t) async {
        await _sent(t, _se, items: 60);
        await t.drag(find.byType(CodeView), const Offset(0, -300));
        await _settle(t);
        final height = t.getSize(find.byType(CodeView)).height;
        expect(height, greaterThanOrEqualTo(0.35 * _se.size.height));
        await t.pump(EditorNotifier.saveDelay);
      },
    );

    testWidgets('an active filter stays visible', (t) async {
      await _sent(t, _phone);
      await t.tap(find.byKey(const Key('response-filter-toggle')));
      await t.pump(const Duration(milliseconds: 300));
      await t.enterText(find.byKey(const Key('response-filter')), r'$[0].name');
      await t.pump(const Duration(milliseconds: 300));
      await t.tap(find.byKey(const Key('response-filter-toggle')));
      await t.pump(const Duration(milliseconds: 300));
      expect(find.byKey(const Key('response-filter')), findsOneWidget);
      await t.pump(EditorNotifier.saveDelay);
    });

    testWidgets('keeps both fields and the Save label on a tablet', (t) async {
      await _sent(t, _desktop);
      expect(find.byKey(const Key('response-search')), findsOneWidget);
      expect(find.byKey(const Key('response-filter')), findsOneWidget);
      expect(find.byKey(const Key('response-search-toggle')), findsNothing);
      expect(find.text('Save'), findsOneWidget);
      await t.pump(EditorNotifier.saveDelay);
    });

    testWidgets('Save is icon only on a phone', (t) async {
      await _sent(t, _phone);
      expect(find.byKey(const Key('response-save')), findsOneWidget);
      expect(find.text('Save'), findsNothing);
      await t.pump(EditorNotifier.saveDelay);
    });
  });
}
