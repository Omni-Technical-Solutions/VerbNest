import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Files that still hold hard-coded `Text('...')` literals. Migrate a file to
/// ARB, then delete it from this list; the test fails if a file here is clean
/// or a file not here regains a literal.
const _pending = <String>{
  'lib/src/widgets/request_editor.dart',
};

final _literal = RegExp(r"(Text|SelectableText)\(\s*'[^'$]*[A-Za-z]");

void main() {
  test('migrated files have no hard-coded Text literals', () {
    final withLiterals = <String>{
      for (final f in Directory('lib/src').listSync(recursive: true))
        if (f is File &&
            f.path.endsWith('.dart') &&
            _literal.hasMatch(f.readAsStringSync()))
          f.path,
    };
    final fresh = withLiterals.difference(_pending);
    final stale = _pending.difference(withLiterals);
    expect(fresh, isEmpty, reason: 'Move these strings to ARB');
    expect(stale, isEmpty, reason: 'Remove these from _pending');
  });

  test('every ARB key exists in every locale', () {
    Set<String> keys(String f) => {
      for (final k in (jsonDecode(File(f).readAsStringSync()) as Map).keys)
        if (!(k as String).startsWith('@')) k,
    };
    final en = keys('lib/l10n/app_en.arb');
    expect(keys('lib/l10n/app_ar.arb'), en);
  });
}
