import 'dart:io';

import 'package:test/test.dart';

import '../tool/gen_prelude.dart' show render;

void main() {
  test('lib/src/prelude.dart is generated from assets/prelude.js', () {
    final js = File('assets/prelude.js').readAsStringSync();
    final current = File('lib/src/prelude.dart').readAsStringSync();
    expect(
      current,
      render(js),
      reason: 'run: dart run tool/gen_prelude.dart',
    );
  });
}
