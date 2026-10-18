import 'dart:io';

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/device_profiles.dart';
import 'support/matrix_support.dart';

/// The licence VerbNest ships and shows is the repository's: the copies in the
/// app's assets must match the root files exactly.
void main() {
  test('the bundled licence and notice are the root LICENSE and NOTICE', () {
    expect(
      File('assets/licenses/VerbNest-Apache-2.0.txt').readAsStringSync(),
      File('../../LICENSE').readAsStringSync(),
    );
    expect(
      File('assets/licenses/VerbNest-NOTICE.txt').readAsStringSync(),
      File('../../NOTICE').readAsStringSync(),
    );
  });

  test('the root LICENSE is the Apache License, Version 2.0', () {
    final text = File('../../LICENSE').readAsStringSync();
    expect(text, contains('Apache License'));
    expect(text, contains('Version 2.0, January 2004'));
  });

  test('every pubspec asset exists', () {
    final pubspec = File('pubspec.yaml').readAsLinesSync();
    final assets = pubspec
        .map((l) => RegExp(r'^\s+- (assets/\S+)$').firstMatch(l)?.group(1))
        .whereType<String>();
    expect(assets, isNotEmpty);
    for (final a in assets) {
      expect(File(a).existsSync(), isTrue, reason: a);
    }
  });

  for (final p in const [
    DeviceProfile('phone-402x874', Size(402, 874)),
    DeviceProfile('desktop-1280x800', Size(1280, 800)),
  ]) {
    testWidgets('Settings opens the licence page, ${p.name}', (t) async {
      await launchApp(t, p);
      await t.tap(find.text('Settings').last);
      await t.pump(const Duration(milliseconds: 500));
      final tile = find.byKey(const Key('licenses'));
      await t.dragUntilVisible(
        tile,
        find.byType(ListView).last,
        const Offset(0, -300),
      );
      await t.ensureVisible(tile);
      await t.pump(const Duration(milliseconds: 300));
      await t.tap(tile);
      await t.pumpAndSettle();
      expect(find.text('VerbNest'), findsWidgets);
      expect(find.textContaining('Apache License, Version 2.0'), findsWidgets);
    });
  }
}
