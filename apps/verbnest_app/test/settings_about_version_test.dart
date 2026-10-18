import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:verbnest_app/src/state/app_info_state.dart';

import 'support/device_profiles.dart';
import 'support/matrix_support.dart';

/// Settings → About shows the installed version and copies it on tap.
void main() {
  test('label drops an empty build number', () {
    expect(const AppVersion(name: '1.2.3', build: '7').label, '1.2.3 (7)');
    expect(const AppVersion(name: '1.2.3', build: '').label, '1.2.3');
  });

  for (final p in const [
    DeviceProfile('phone-402x874', Size(402, 874)),
    DeviceProfile('desktop-1280x800', Size(1280, 800)),
  ]) {
    testWidgets('About shows the version and copies it, ${p.name}', (t) async {
      PackageInfo.setMockInitialValues(
        appName: 'VerbNest',
        packageName: 'com.omni.verbnest',
        version: '0.64.5',
        buildNumber: '47',
        buildSignature: '',
      );
      String? copied;
      t.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform,
        (call) async {
          if (call.method == 'Clipboard.setData') {
            copied = (call.arguments as Map)['text'] as String;
          }
          return null;
        },
      );
      addTearDown(
        () => t.binding.defaultBinaryMessenger.setMockMethodCallHandler(
          SystemChannels.platform,
          null,
        ),
      );
      await launchApp(t, p);
      await t.tap(find.text('Settings').last);
      await t.pump(const Duration(milliseconds: 500));

      final tile = find.byKey(const Key('app-version'));
      await t.dragUntilVisible(
        tile,
        find.byType(ListView).last,
        const Offset(0, -300),
      );
      await t.pump(const Duration(milliseconds: 300));
      expect(find.text('0.64.5 (47)'), findsOneWidget);
      await t.tap(tile);
      await t.pump();
      expect(copied, 'VerbNest 0.64.5 (47)');
      expect(find.text('Version copied'), findsOneWidget);
    });
  }
}
