import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:verbnest_app/src/state/editor_state.dart';

import 'support/device_profiles.dart';
import 'support/matrix_support.dart';

Future<void> _sent(WidgetTester t, DeviceProfile p) async {
  final a = await launchApp(t, p);
  await openRequest(a, p);
  await t.tap(find.byKey(const Key('send')));
  await t.pump(const Duration(seconds: 1));
  await t.pump(const Duration(seconds: 1));
}

void main() {
  const phone = DeviceProfile('iphone-402x874', Size(402, 874));
  const desktop = DeviceProfile('desktop-1280x800', Size(1280, 800));

  testWidgets('timings open as a bottom sheet on a phone', (t) async {
    await _sent(t, phone);
    await t.tap(find.byKey(const Key('response-timing')));
    await t.pumpAndSettle();
    expect(find.byKey(const Key('detail-sheet')), findsOneWidget);
    expect(find.byKey(const Key('timing-rows')), findsOneWidget);
    expect(find.byType(AlertDialog), findsNothing);
    expect(find.text('Timing'), findsOneWidget);
    await t.pump(EditorNotifier.saveDelay);
  });

  testWidgets('the sheet is dismissed by swiping it down', (t) async {
    await _sent(t, phone);
    await t.tap(find.byKey(const Key('response-timing')));
    await t.pumpAndSettle();
    await t.drag(find.byKey(const Key('detail-sheet')), const Offset(0, 600));
    await t.pumpAndSettle();
    expect(find.byKey(const Key('detail-sheet')), findsNothing);
    await t.pump(EditorNotifier.saveDelay);
  });

  testWidgets('the sheet can be dragged taller', (t) async {
    await _sent(t, phone);
    await t.tap(find.byKey(const Key('response-timing')));
    await t.pumpAndSettle();
    final before = t.getSize(find.byType(DraggableScrollableSheet)).height;
    await t.drag(find.byKey(const Key('detail-sheet')), const Offset(0, -300));
    await t.pumpAndSettle();
    expect(
      t.getSize(find.byType(DraggableScrollableSheet)).height,
      greaterThanOrEqualTo(before),
    );
    await t.pump(EditorNotifier.saveDelay);
  });

  testWidgets('a wide window keeps the dialog with a Close button', (t) async {
    await _sent(t, desktop);
    await t.tap(find.byKey(const Key('response-timing')));
    await t.pumpAndSettle();
    expect(find.byType(AlertDialog), findsOneWidget);
    expect(find.byKey(const Key('detail-sheet')), findsNothing);
    expect(find.byKey(const Key('timing-rows')), findsOneWidget);
    await t.tap(find.text('Close'));
    await t.pumpAndSettle();
    expect(find.byType(AlertDialog), findsNothing);
    await t.pump(EditorNotifier.saveDelay);
  });
}
