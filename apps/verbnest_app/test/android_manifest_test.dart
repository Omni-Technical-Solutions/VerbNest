import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// VerbNest is local-first: nothing may reach Google's backup or another
/// device by itself (security review S1, docs/spec/security-and-complexity-plan.md).
void main() {
  final manifest = File('android/app/src/main/AndroidManifest.xml')
      .readAsStringSync();

  test('Android Auto Backup is off', () {
    expect(manifest, contains('android:allowBackup="false"'));
  });

  test('backup and device transfer exclude everything', () {
    expect(
      manifest,
      contains('android:dataExtractionRules="@xml/data_extraction_rules"'),
    );
    final rules = File('android/app/src/main/res/xml/data_extraction_rules.xml')
        .readAsStringSync();
    for (final section in ['cloud-backup', 'device-transfer']) {
      final body = RegExp('<$section>([\\s\\S]*?)</$section>')
          .firstMatch(rules)
          ?.group(1);
      expect(body, isNotNull, reason: section);
      for (final domain in ['root', 'file', 'database', 'sharedpref']) {
        expect(
          body,
          contains('<exclude domain="$domain"'),
          reason: '$section $domain',
        );
      }
      // No include: nothing is opted back in.
      expect(body, isNot(contains('<include')), reason: section);
    }
  });

  test('the Android cleartext policy is not loosened', () {
    // Requests go through dart:io, which the policy does not govern (checked
    // on an Android 15 emulator: http:// to the host works without the flag),
    // so the flag would only loosen it for other components (S7).
    expect(manifest, isNot(contains('usesCleartextTraffic')));
  });
}
