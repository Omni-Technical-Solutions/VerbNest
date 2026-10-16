import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:verbnest_app/src/state/editor_state.dart';
import 'package:verbnest_app/src/widgets/result_table_view.dart';

import 'support/device_profiles.dart';
import 'support/matrix_support.dart';

/// The results table at every device size, with and without the keyboard, and
/// at 200% and 310% text: open it from the response, scroll it, open a value,
/// and see no overflow.
Future<void> openTable(WidgetTester t) async {
  // A phone-width pane has the table in the body menu, a wide one a segment.
  final more = find.byKey(const Key('body-more'));
  if (more.evaluate().isNotEmpty) {
    await t.ensureVisible(more);
    await t.tap(more);
    await t.pumpAndSettle();
    await t.tap(find.byKey(const Key('menu-table')));
  } else {
    await t.tap(
      find.descendant(
        of: find.byKey(const Key('body-view')),
        matching: find.text('Table'),
      ),
    );
  }
  await t.pump(const Duration(milliseconds: 300));
}

Future<void> sendAndOpenTable(MatrixApp a, DeviceProfile p) async {
  final t = a.t;
  await openRequest(a, p);
  await t.tap(find.byKey(const Key('send')), warnIfMissed: false);
  await t.pump(const Duration(seconds: 1));
  await t.pump(const Duration(seconds: 1));
  await openTable(t);
}

Future<void> exercise(MatrixApp a, DeviceProfile p) async {
  final t = a.t;
  await sendAndOpenTable(a, p);
  expect(find.byType(ResultTableView), findsOneWidget);
  // Scroll sideways and down, then open a value.
  final body = find.byKey(const Key('result-table-body'));
  final at = t.getTopLeft(body) + const Offset(80, 30);
  await t.dragFrom(at, const Offset(-200, 0));
  await t.pump();
  await t.dragFrom(at, const Offset(0, -80));
  await t.pump();
  await t.tapAt(t.getTopLeft(body) + const Offset(90, 24));
  await t.pumpAndSettle();
  await t.sendKeyEvent(LogicalKeyboardKey.escape);
  await t.pumpAndSettle();
  // With the keyboard up, the row filter (the search box) stays usable.
  if (p.keyboard > 0) {
    final toggle = find.byKey(const Key('response-search-toggle'));
    if (toggle.evaluate().isNotEmpty) {
      await t.tap(toggle);
      await t.pump(const Duration(milliseconds: 300));
    }
    final search = find.byKey(const Key('response-search'));
    if (search.evaluate().isNotEmpty) {
      await raiseKeyboard(a, p, search);
    }
  }
}

void main() {
  for (final p in allDeviceProfiles) {
    testWidgets('the results table fits ${p.name}', (t) async {
      final a = await launchApp(t, p, engine: FakeEngine(items: 40));
      final errors = await collectErrors(() => exercise(a, p));
      expect(errors, isEmpty, reason: errors.toSet().join(' | '));
      await t.pump(EditorNotifier.saveDelay);
    });
  }

  final big = [
    phoneProfiles.firstWhere((p) => p.name == 'se-320x568'),
    phoneProfiles.firstWhere((p) => p.name == 'android-360x640'),
    phoneProfiles.firstWhere((p) => p.name == 'iphone-402x874'),
    phoneProfiles.firstWhere((p) => p.name == 'landscape-667x375'),
    phoneProfiles.firstWhere((p) => p.name == 'landscape-874x402'),
  ];
  for (final scale in [2.0, 3.1]) {
    for (final p in big) {
      testWidgets(
        'the results table fits ${p.name} at ${(scale * 100).round()}% text',
        (t) async {
          t.platformDispatcher.textScaleFactorTestValue = scale;
          addTearDown(t.platformDispatcher.clearTextScaleFactorTestValue);
          final a = await launchApp(t, p, engine: FakeEngine(items: 40));
          final errors = await collectErrors(() => exercise(a, p));
          expect(errors, isEmpty, reason: errors.toSet().join(' | '));
          await t.pump(EditorNotifier.saveDelay);
        },
      );
    }
  }
}
