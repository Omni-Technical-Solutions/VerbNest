import 'dart:convert';
import 'dart:io';

import 'dart:ui' show Locale;

import 'package:flutter_test/flutter_test.dart';
import 'package:verbnest_app/l10n/app_localizations.dart';

/// Files that still hold hard-coded `Text('...')` literals. Migrate a file to
/// ARB, then delete it from this list; the test fails if a file here is clean
/// or a file not here regains a literal.
const _pending = <String>{};

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

  test('English is the only language the app ships', () {
    // Arabic was removed in v0.58.0. Adding a language again means adding its
    // ARB file and widening this test, so it cannot happen by accident.
    final arb = [
      for (final f in Directory('lib/l10n').listSync())
        if (f is File && f.path.endsWith('.arb')) f.uri.pathSegments.last,
    ];
    expect(arb, ['app_en.arb']);
    expect(AppLocalizations.supportedLocales, [const Locale('en')]);
  });

  test('every ARB key is a valid identifier or metadata', () {
    final keys = (jsonDecode(
      File('lib/l10n/app_en.arb').readAsStringSync(),
    ) as Map).keys.cast<String>();
    final bad = [
      for (final k in keys)
        if (!k.startsWith('@') && !RegExp(r'^[a-z][A-Za-z0-9]*$').hasMatch(k))
          k,
    ];
    expect(bad, isEmpty);
  });
}
