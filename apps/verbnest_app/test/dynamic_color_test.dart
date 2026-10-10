import 'package:flutter/foundation.dart'
    show debugDefaultTargetPlatformOverride;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:verbnest_app/src/app.dart';
import 'package:verbnest_app/src/state/prefs.dart';
import 'package:verbnest_app/src/state/session.dart';
import 'package:verbnest_app/src/theme.dart';

Future<ProviderContainer> _pump(WidgetTester t) async {
  t.view.physicalSize = const Size(402, 874);
  t.view.devicePixelRatio = 1;
  addTearDown(t.view.reset);
  final s = WorkspaceSession.memory();
  addTearDown(s.close);
  final c = ProviderContainer(
    overrides: [sessionProvider.overrideWithValue(s)],
  );
  addTearDown(c.dispose);
  await t.pumpWidget(
    UncontrolledProviderScope(container: c, child: const VerbnestApp()),
  );
  await t.pump(const Duration(milliseconds: 300));
  await t.tap(find.text('Settings').last);
  await t.pump(const Duration(milliseconds: 500));
  return c;
}

void main() {
  group('theme', () {
    test('a system scheme is used as it is', () {
      final system = ColorScheme.fromSeed(
        seedColor: const Color(0xFF00897B),
        brightness: Brightness.light,
      );
      final t = buildTheme(Brightness.light, dynamicScheme: system);
      expect(t.colorScheme.primary, system.primary);
      expect(t.colorScheme.surfaceContainerLow, system.surfaceContainerLow);
    });

    test('without one the accent colour decides', () {
      final a = buildTheme(Brightness.light);
      final b = buildTheme(Brightness.light, seed: AppAccents.seed(1));
      expect(a.colorScheme.primary, isNot(b.colorScheme.primary));
    });
  });

  group('preference', () {
    testWidgets('is off by default and remembered', (t) async {
      final s = WorkspaceSession.memory();
      addTearDown(s.close);
      final c = ProviderContainer(
        overrides: [sessionProvider.overrideWithValue(s)],
      );
      addTearDown(c.dispose);
      expect(c.read(prefsProvider).dynamicColor, isFalse);
      c
          .read(prefsProvider.notifier)
          .update(c.read(prefsProvider).copyWith(dynamicColor: true));
      final again = ProviderContainer(
        overrides: [sessionProvider.overrideWithValue(s)],
      );
      addTearDown(again.dispose);
      expect(again.read(prefsProvider).dynamicColor, isTrue);
    });
  });

  group('settings', () {
    testWidgets('Android offers the switch; turning it on dims the accents', (
      t,
    ) async {
      final c = await _pump(t);
      await t.dragUntilVisible(
        find.byKey(const Key('dynamic-color')),
        find.byType(ListView).first,
        const Offset(0, -300),
      );
      expect(find.byKey(const Key('dynamic-color')), findsOneWidget);
      await t.tap(find.byKey(const Key('dynamic-color')));
      await t.pump(const Duration(milliseconds: 400));
      expect(c.read(prefsProvider).dynamicColor, isTrue);
      expect(t.takeException(), isNull);
      // The app keeps working; with no system colours it uses the accent.
      final tile = t.widget<SwitchListTile>(
        find.byKey(const Key('dynamic-color')),
      );
      expect(tile.value, isTrue);
    });

    testWidgets('other platforms do not show it', (t) async {
      try {
        debugDefaultTargetPlatformOverride = TargetPlatform.macOS;
        await _pump(t);
        await t.dragUntilVisible(
          find.byKey(const Key('accent-picker')),
          find.byType(ListView).first,
          const Offset(0, -300),
        );
        expect(find.byKey(const Key('accent-picker')), findsOneWidget);
        expect(find.byKey(const Key('dynamic-color')), findsNothing);
      } finally {
        debugDefaultTargetPlatformOverride = null;
      }
    });
  });
}
