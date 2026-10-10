import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter/widgets.dart';
import 'package:verbnest_app/src/state/editor_state.dart';
import 'package:verbnest_app/src/state/tree_state.dart';

import 'support/device_profiles.dart';
import 'support/matrix_support.dart';

/// Profiles whose checks are known to fail, with the phase of
/// docs/spec/mobile-adaptive-plan.md that fixes them. A profile listed here is
/// skipped; the list shrinks as the phases land and ends empty.
const _knownEditorFailures = <String, String>{
  'android-360x640+keyboard': 'phase 1',
  'landscape-667x375+keyboard': 'phase 1',
  'landscape-740x360+keyboard': 'phase 1',
  'landscape-874x402+keyboard': 'phase 1',
  'landscape-932x430+keyboard': 'phase 1',
};
const _knownReachFailures = <String, String>{
  'landscape-740x360+keyboard': 'phase 1',
  'landscape-874x402+keyboard': 'phase 3',
};

void main() {
  group('request editor with a response has no overflow', () {
    for (final p in allDeviceProfiles) {
      final known = _knownEditorFailures[p.name];
      testWidgets(p.name, (t) async {
        final a = await launchApp(t, p);
        final errors = await collectErrors(() async {
          await openRequest(a, p);
          await raiseKeyboard(a, p, find.byKey(const Key('url')));
          await t.tap(find.byKey(const Key('send')), warnIfMissed: false);
          await t.pump(const Duration(seconds: 1));
          await t.pump(const Duration(seconds: 1));
        });
        expect(errors, isEmpty, reason: errors.toSet().join(' | '));
        await t.pump(EditorNotifier.saveDelay);
      }, skip: known != null);
    }
  });

  group('the URL field and Send stay above the keyboard', () {
    for (final p in allDeviceProfiles.where((p) => p.keyboard > 0)) {
      final known = _knownReachFailures[p.name];
      testWidgets(p.name, (t) async {
        final a = await launchApp(t, p);
        await collectErrors(() async {
          await openRequest(a, p);
          await raiseKeyboard(a, p, find.byKey(const Key('url')));
        });
        final visibleBottom = p.size.height - p.keyboard;
        for (final key in ['url', 'send']) {
          final finder = find.byKey(Key(key));
          expect(finder, findsOneWidget, reason: key);
          final r = t.getRect(finder);
          expect(r.top, greaterThanOrEqualTo(0), reason: '$key top');
          expect(
            r.bottom,
            lessThanOrEqualTo(visibleBottom + 0.5),
            reason: '$key is under the keyboard (visible to $visibleBottom)',
          );
        }
        await t.pump(EditorNotifier.saveDelay);
      }, skip: known != null);
    }
  });

  group('other screens have no overflow', () {
    for (final p in allDeviceProfiles.where((p) => p.keyboard == 0)) {
      testWidgets(p.name, (t) async {
        final a = await launchApp(t, p);
        final errors = await collectErrors(() async {
          for (final label in ['History', 'Environments', 'Settings']) {
            await t.tap(find.text(label).last);
            await t.pump(const Duration(milliseconds: 500));
          }
          await t.tap(find.text('Environments').last);
          await t.pump(const Duration(milliseconds: 500));
          await t.tap(find.text('Development'));
          await t.pump(const Duration(milliseconds: 500));
        });
        expect(errors, isEmpty, reason: errors.toSet().join(' | '));
        expect(a.c.read(tabsProvider).open, isEmpty);
      });
    }
  });
}
