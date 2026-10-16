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
        // The button brings the request back, and again takes it away.
        await t.ensureVisible(find.byKey(const Key('maximize-response')));
        await t.tap(find.byKey(const Key('maximize-response')));
        await t.pump();
        expect(t.getSize(grid).height, lessThanOrEqualTo(shown));
        await t.ensureVisible(find.byKey(const Key('maximize-response')));
        await t.tap(find.byKey(const Key('maximize-response')));
        await t.pump();
        expect(t.getSize(grid).height, shown);
        await t.pump(EditorNotifier.saveDelay);
      },
    );
  }
}
