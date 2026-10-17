import 'dart:io';

import 'package:test/test.dart';

import '../tool/gen_prelude.dart' show render;

void main() {
  test('lib/src/prelude.dart is generated from assets/prelude.js', () {
    // Line endings are not part of the comparison: a Windows checkout may
    // have turned them into CRLF.
    String lf(String s) => s.replaceAll('\r\n', '\n');
    final js = lf(File('assets/prelude.js').readAsStringSync());
    final current = lf(File('lib/src/prelude.dart').readAsStringSync());
    expect(current, render(js), reason: 'run: dart run tool/gen_prelude.dart');
  });
}
