import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Files that still hold hard-coded `Text('...')` literals. Migrate a file to
/// ARB, then delete it from this list; the test fails if a file here is clean
/// or a file not here regains a literal.
const _pending = <String>{
  'lib/src/widgets/request_editor.dart',
  'lib/src/widgets/response_view.dart',
  'lib/src/widgets/collections_sidebar.dart',
  'lib/src/widgets/network_settings.dart',
  'lib/src/widgets/auth_editor.dart',
  'lib/src/widgets/graphql_editor.dart',
  'lib/src/pages/workspaces_dialog.dart',
  'lib/src/pages/runner_page.dart',
  'lib/src/widgets/request_extras.dart',
  'lib/src/widgets/code_dialog.dart',
  'lib/src/widgets/cookie_manager.dart',
  'lib/src/pages/console_page.dart',
  'lib/src/widgets/env_selector.dart',
  'lib/src/pages/revisions_dialog.dart',
  'lib/src/widgets/token_manager.dart',
  'lib/src/widgets/kv_editor.dart',
  'lib/src/widgets/scripts_editor.dart',
  'lib/src/settings_page.dart',
  'lib/src/pages/history_page.dart',
  'lib/src/widgets/name_dialog.dart',
  'lib/src/pages/environments_page.dart',
  'lib/src/widgets/assertions_editor.dart',
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
