import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// The macOS app renders with Skia (Metal), not Impeller: Impeller's
/// distance-field text corrupts and blurs glyphs on dual-GPU Intel Macs
/// (seen in 0.64.2 in the response body and the results table).
void main() {
  test('the macOS app opts out of Impeller', () {
    final plist = File('macos/Runner/Info.plist').readAsStringSync();
    expect(
      RegExp(r'<key>FLTEnableImpeller</key>\s*<false/>').hasMatch(plist),
      isTrue,
    );
  });
}
