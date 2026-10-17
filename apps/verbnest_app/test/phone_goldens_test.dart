@Tags(['golden'])
library;

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:verbnest_app/src/state/editor_state.dart';

import 'support/device_profiles.dart';
import 'support/golden_setup.dart';
import 'support/matrix_support.dart';

/// The request editor with a response at the sizes in
/// docs/spec/mobile-adaptive-plan.md, so layout work is reviewed by eye.
/// Regenerate with `flutter test --update-goldens test/phone_goldens_test.dart`
/// and look at the images before committing them.
void main() {
  setUpAll(() async {
    await loadGoldenFonts();
    useTolerantGoldens('test/phone_goldens_test.dart');
  });

  final shown = [
    phoneProfiles.firstWhere((p) => p.name == 'se-320x568'),
    phoneProfiles.firstWhere((p) => p.name == 'se-320x568').withKeyboard(),
    phoneProfiles.firstWhere((p) => p.name == 'android-360x640'),
    phoneProfiles.firstWhere((p) => p.name == 'iphone-402x874'),
    phoneProfiles.firstWhere((p) => p.name == 'landscape-667x375'),
    phoneProfiles.firstWhere((p) => p.name == 'landscape-874x402'),
  ];

  for (final p in shown) {
    testWidgets('editor with a response, ${p.name}', (t) async {
      final a = await launchApp(t, p);
      await openRequest(a, p);
      await raiseKeyboard(a, p, find.byKey(const Key('url')));
      await t.tap(find.byKey(const Key('send')), warnIfMissed: false);
      await t.pump(const Duration(seconds: 1));
      await t.pump(const Duration(seconds: 1));
      await expectLater(
        find.byType(WidgetsApp),
        matchesGoldenFile('goldens/phone-${p.name}.png'),
      );
      await t.pump(EditorNotifier.saveDelay);
    });
  }
}
