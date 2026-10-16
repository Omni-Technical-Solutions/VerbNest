import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:verbnest_app/src/state/editor_state.dart';

import 'device_matrix_table_test.dart' show sendAndOpenTable;
import 'support/device_profiles.dart';
import 'support/matrix_support.dart';

/// The table must show real rows in the default layout of common Mac windows.
void main() {
  for (final size in const [
    Size(1280, 800),
    Size(1440, 900),
    Size(1000, 700),
  ]) {
    testWidgets(
      'the table shows rows at ${size.width.round()}x${size.height.round()}',
      (t) async {
        final p = DeviceProfile('mac', size);
        final a = await launchApp(t, p, engine: FakeEngine(items: 40));
        await sendAndOpenTable(a, p);
        final grid = find.byKey(const Key('result-table-body'));
        expect(grid, findsOneWidget);
        // At least five rows of 32 px are in view.
        // Choosing the table gives the response the whole editor.
        await t.pump(const Duration(milliseconds: 500));
        final shown = t.getSize(grid).height;
        expect(shown, greaterThanOrEqualTo(180));
        // The button switches the request pane away and back.
        await t.ensureVisible(find.byKey(const Key('maximize-response')));
        await t.tap(find.byKey(const Key('maximize-response')));
        await t.pump();
        await t.ensureVisible(find.byKey(const Key('maximize-response')));
        await t.tap(find.byKey(const Key('maximize-response')));
        await t.pump();
        expect(t.getSize(grid).height, shown);
        await t.pump(EditorNotifier.saveDelay);
      },
    );
  }

  // A change of view is one swap: the first frame after the tap is already
  // the final layout (no step a frame later), and the table sits on whole
  // pixels so nothing in it is drawn soft.
  for (final size in const [Size(1280, 800), Size(1000, 700)]) {
    testWidgets(
      'changing the body view settles in one frame at ${size.width.round()}x${size.height.round()}',
      (t) async {
        final p = DeviceProfile('mac', size);
        final a = await launchApp(t, p, engine: FakeEngine(items: 40));
        await openRequest(a, p);
        await t.tap(find.byKey(const Key('send')), warnIfMissed: false);
        await t.pump(const Duration(seconds: 1));
        await t.pump(const Duration(seconds: 1));
        final status = find.byKey(const Key('response-status'));
        for (final mode in ['Table', 'Raw', 'Pretty', 'Hex', 'Table']) {
          final seg = find.descendant(
            of: find.byKey(const Key('body-view')),
            matching: find.text(mode),
          );
          await t.ensureVisible(seg);
          await t.pump();
          await t.tap(seg);
          await t.pump();
          final first = t.getRect(status);
          final grid = find.byKey(const Key('result-table-body'));
          final gridFirst = grid.evaluate().isEmpty ? null : t.getRect(grid);
          await t.pump(const Duration(milliseconds: 500));
          expect(t.getRect(status), first, reason: 'status moved after $mode');
          if (gridFirst != null) {
            expect(t.getRect(grid), gridFirst, reason: 'grid moved ($mode)');
            final o = gridFirst.topLeft;
            expect(o.dx, o.dx.roundToDouble(), reason: 'grid x $o');
            expect(o.dy, o.dy.roundToDouble(), reason: 'grid y $o');
          }
        }
        await t.pump(EditorNotifier.saveDelay);
      },
    );
  }
}
