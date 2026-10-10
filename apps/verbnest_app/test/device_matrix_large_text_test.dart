import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:verbnest_app/src/state/editor_state.dart';

import 'support/device_profiles.dart';
import 'support/matrix_support.dart';

/// Large text across the device sizes of docs/spec/mobile-adaptive-plan.md:
/// the request editor with a response, every request tab and the other
/// screens at 200% and at iOS's largest accessibility size (310%). Entries in
/// the map are skipped and name the fix still to do; it ends empty.
const _known = <String, String>{};

const _tabs = [
  'Params',
  'Headers',
  'Auth',
  'Body',
  'Scripts',
  'Assertions',
  'Settings',
];

final _profiles = [
  phoneProfiles.firstWhere((p) => p.name == 'se-320x568'),
  phoneProfiles.firstWhere((p) => p.name == 'android-360x640'),
  phoneProfiles.firstWhere((p) => p.name == 'iphone-402x874'),
  phoneProfiles.firstWhere((p) => p.name == 'landscape-667x375'),
  phoneProfiles.firstWhere((p) => p.name == 'landscape-874x402'),
];

void main() {
  for (final scale in [2.0, 3.1]) {
    group('text at ${(scale * 100).round()}%', () {
      for (final p in _profiles) {
        final name = '${p.name}@${(scale * 100).round()}';
        testWidgets('editor, tabs and screens fit on ${p.name}', (t) async {
          t.platformDispatcher.textScaleFactorTestValue = scale;
          addTearDown(t.platformDispatcher.clearTextScaleFactorTestValue);
          final a = await launchApp(t, p);
          final errors = await collectErrors(() async {
            await openRequest(a, p);
            await t.tap(find.byKey(const Key('send')), warnIfMissed: false);
            await t.pump(const Duration(seconds: 1));
            await t.pump(const Duration(seconds: 1));
            // On a phone the send moved to the response; back to the request.
            if (find.byKey(const Key('pane-switch')).evaluate().isNotEmpty) {
              await t.tap(find.text('Request'));
              await t.pump(const Duration(milliseconds: 400));
            }
            for (final tab in _tabs) {
              final finder = find.text(tab).first;
              await t.ensureVisible(finder);
              await t.pump(const Duration(milliseconds: 100));
              await t.tap(finder, warnIfMissed: false);
              await t.pump(const Duration(milliseconds: 300));
            }
          });
          expect(errors, isEmpty, reason: errors.toSet().join(' | '));
          await t.pump(EditorNotifier.saveDelay);
        }, skip: _known.containsKey(name));
      }
    });
  }
}
