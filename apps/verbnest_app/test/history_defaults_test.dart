import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:verbnest_app/src/state/prefs.dart';
import 'package:verbnest_app/src/state/session.dart';

/// Security review S2: history keeps response bodies unencrypted on the
/// device, so a phone or tablet does not keep them until the user says so.
bool bodiesOn(TargetPlatform platform, {bool stored = false, bool? value}) {
  debugDefaultTargetPlatformOverride = platform;
  try {
    final s = WorkspaceSession.memory();
    addTearDown(s.close);
    if (stored) {
      s.local.setKv(s.repo.workspaceId, 'pref.historyBodies', '$value');
    }
    final c = ProviderContainer(
      overrides: [sessionProvider.overrideWithValue(s)],
    );
    addTearDown(c.dispose);
    return c.read(prefsProvider).historyBodies;
  } finally {
    debugDefaultTargetPlatformOverride = null;
  }
}

void main() {
  test('phones and tablets do not keep bodies by default', () {
    expect(bodiesOn(TargetPlatform.android), isFalse);
    expect(bodiesOn(TargetPlatform.iOS), isFalse);
  });

  test('computers keep bodies by default', () {
    for (final p in [
      TargetPlatform.macOS,
      TargetPlatform.windows,
      TargetPlatform.linux,
    ]) {
      expect(bodiesOn(p), isTrue, reason: '$p');
    }
  });

  test('a saved choice wins on every platform', () {
    expect(bodiesOn(TargetPlatform.android, stored: true, value: true), isTrue);
    expect(bodiesOn(TargetPlatform.macOS, stored: true, value: false), isFalse);
  });
}
