
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart'
    show DropdownMenu, SegmentedButton, Text;

import 'support/device_profiles.dart';
import 'support/matrix_support.dart';

/// English is the only language: Settings offers no language choice and shows
/// no Arabic (a saved choice used to be possible before v0.58.0).
void main() {
  for (final p in const [
    DeviceProfile('phone-402x874', Size(402, 874)),
    DeviceProfile('desktop-1280x800', Size(1280, 800)),
  ]) {
    testWidgets('settings has no language control, ${p.name}', (t) async {
      await launchApp(t, p);
      await t.tap(find.text('Settings').last);
      await t.pump(const Duration(milliseconds: 500));

      final texts = [
        for (final w in t.widgetList<Text>(
          find.byType(Text, skipOffstage: false),
        ))
          w.data ?? w.textSpan?.toPlainText() ?? '',
      ];
      final arabic = RegExp(r'[؀-ۿ]');
      expect(texts.where(arabic.hasMatch), isEmpty);
      expect(
        texts.where((s) => s.toLowerCase().contains('language')),
        isEmpty,
        reason: 'no language setting',
      );
      expect(find.text('English', skipOffstage: false), findsNothing);
      expect(find.byKey(const Key('language')), findsNothing);
      // Nothing in Settings is a locale picker.
      expect(
        find.byType(DropdownMenu<Locale>, skipOffstage: false),
        findsNothing,
      );
      expect(
        find.byType(SegmentedButton<Locale>, skipOffstage: false),
        findsNothing,
      );
    });
  }
}
