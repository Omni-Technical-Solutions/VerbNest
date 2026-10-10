import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:verbnest_app/src/state/editor_state.dart';
import 'package:verbnest_core/verbnest_core.dart';

import 'support/device_profiles.dart';
import 'support/matrix_support.dart';

/// The other screens of docs/spec/mobile-adaptive-plan.md, phase 5: every
/// request tab, the GraphQL editor, the runner and the dialogs, at every size
/// and with the keyboard up or down. Profiles listed in a map are skipped and
/// name the fix still to do; the maps end empty.
const _knownTabFailures = <String, String>{};
const _knownGraphqlFailures = <String, String>{};
const _knownRunnerFailures = <String, String>{};
const _knownDialogFailures = <String, String>{};

const _tabs = [
  'Params',
  'Headers',
  'Auth',
  'Body',
  'Scripts',
  'Assertions',
  'Settings',
];

/// Taps a tab even when it is scrolled out of the row.
Future<void> _tapTab(WidgetTester t, String label) async {
  final tab = find.text(label).first;
  await t.ensureVisible(tab);
  await t.pump(const Duration(milliseconds: 100));
  await t.tap(tab, warnIfMissed: false);
  await t.pump(const Duration(milliseconds: 400));
}

HttpRequestItem _graphql() => HttpRequestItem(
  id: '',
  name: 'Pets query',
  method: 'POST',
  url: 'https://api.petstore.dev/graphql',
  body: const GraphqlBody(
    query: 'query Pets(\$limit: Int) {\n  pets(limit: \$limit) {\n    id\n    name\n  }\n}',
    variables: '{"limit": 20}',
  ),
);

void main() {
  group('every request tab has no overflow', () {
    for (final p in allDeviceProfiles) {
      final known = _knownTabFailures[p.name];
      testWidgets(p.name, (t) async {
        final a = await launchApp(t, p);
        final errors = await collectErrors(() async {
          await openRequest(a, p);
          await raiseKeyboard(a, p, find.byKey(const Key('url')));
          for (final tab in _tabs) {
            await _tapTab(t, tab);
          }
        });
        expect(errors, isEmpty, reason: errors.toSet().join(' | '));
        await t.pump(EditorNotifier.saveDelay);
      }, skip: known != null);
    }
  });

  group('the GraphQL editor has no overflow', () {
    for (final p in allDeviceProfiles) {
      final known = _knownGraphqlFailures[p.name];
      testWidgets(p.name, (t) async {
        final a = await launchApp(t, p, request: _graphql());
        final errors = await collectErrors(() async {
          await openRequest(a, p);
          await _tapTab(t, 'Body');
          await raiseKeyboard(a, p, find.byKey(const Key('url')));
        });
        expect(errors, isEmpty, reason: errors.toSet().join(' | '));
        await t.pump(EditorNotifier.saveDelay);
      }, skip: known != null);
    }
  });

  group('the collection runner has no overflow', () {
    for (final p in allDeviceProfiles.where((p) => p.keyboard == 0)) {
      final known = _knownRunnerFailures[p.name];
      testWidgets(p.name, (t) async {
        final a = await launchApp(t, p);
        final errors = await collectErrors(() async {
          if (find.byKey(Key('node-${a.id}')).evaluate().isEmpty) {
            await t.tap(find.byKey(Key('node-${a.col}')));
            await t.pump(const Duration(milliseconds: 300));
          }
          await t.tap(find.byKey(Key('menu-${a.col}')));
          await t.pumpAndSettle();
          await t.tap(find.text('Run…'));
          await t.pumpAndSettle();
        });
        expect(errors, isEmpty, reason: errors.toSet().join(' | '));
      }, skip: known != null);
    }
  });

  group('dialogs have no overflow', () {
    for (final p in allDeviceProfiles.where((p) => p.keyboard == 0)) {
      final known = _knownDialogFailures[p.name];
      testWidgets(p.name, (t) async {
        final a = await launchApp(t, p);
        final errors = await collectErrors(() async {
          if (find.byKey(Key('node-${a.id}')).evaluate().isEmpty) {
            await t.tap(find.byKey(Key('node-${a.col}')));
            await t.pump(const Duration(milliseconds: 300));
          }
          // Generate code, from the request's menu.
          await t.tap(find.byKey(Key('menu-${a.id}')));
          await t.pumpAndSettle();
          await t.tap(find.text('Generate code…'));
          await t.pumpAndSettle();
          await t.tapAt(const Offset(2, 2));
          await t.pumpAndSettle();
        });
        expect(errors, isEmpty, reason: errors.toSet().join(' | '));
      }, skip: known != null);
    }
  });
}
