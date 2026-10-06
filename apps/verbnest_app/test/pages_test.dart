import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:verbnest_app/src/pages/environments_page.dart';
import 'package:verbnest_app/src/pages/history_page.dart';
import 'package:verbnest_app/src/settings_page.dart';
import 'package:verbnest_app/src/state/session.dart';
import 'package:verbnest_storage/verbnest_storage.dart';

Future<WorkspaceSession> pump(WidgetTester tester, Widget page) async {
  tester.view.physicalSize = const Size(1000, 900);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  final s = WorkspaceSession.memory();
  addTearDown(s.close);
  await tester.pumpWidget(
    ProviderScope(
      overrides: [sessionProvider.overrideWithValue(s)],
      child: MaterialApp(home: Scaffold(body: page)),
    ),
  );
  return s;
}

void main() {
  settingsAndShortcutTests();
  testWidgets('environments: add environment and a variable', (tester) async {
    final s = await pump(tester, const EnvironmentsPage());
    await tester.tap(find.byKey(const Key('env-add')));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField).last, 'Staging');
    await tester.tap(find.text('Create'));
    await tester.pumpAndSettle();
    expect(s.repo.environments().single.name, 'Staging');

    await tester.tap(find.byKey(const Key('var-add')));
    await tester.pump();
    await tester.enterText(find.byKey(const ValueKey('var-key-0')), 'host');
    await tester.enterText(
      find.byKey(const ValueKey('var-value-0-false')),
      'h',
    );
    await tester.pump();
    final vars = s.repo.environments().single.variables;
    expect(vars.single.key, 'host');
    expect(vars.single.value, 'h');
  });

  testWidgets('history: lists entries and filters', (tester) async {
    final s = await pump(tester, const HistoryPage());
    for (final (i, url) in ['http://a.test/x', 'http://b.test/y'].indexed) {
      s.local.addHistory(
        HistoryEntry(
          id: 'H$i',
          workspaceId: s.repo.workspaceId,
          method: 'GET',
          url: url,
          sentAt: DateTime(2025, 1, 1, 0, i),
          status: 200,
          requestJson: '{}',
        ),
      );
    }
    await tester.pumpWidget(
      ProviderScope(
        overrides: [sessionProvider.overrideWithValue(s)],
        child: const MaterialApp(home: Scaffold(body: HistoryPage())),
      ),
    );
    expect(find.textContaining('a.test'), findsOneWidget);
    expect(find.textContaining('b.test'), findsOneWidget);
    await tester.enterText(find.byKey(const Key('history-search')), 'b.test');
    await tester.pump();
    expect(find.textContaining('a.test'), findsNothing);
  });
}

void settingsAndShortcutTests() {
  testWidgets('settings persist workspace HTTP defaults', (tester) async {
    final s = await pump(tester, const SettingsPage());
    await tester.tap(find.byKey(const Key('default-verify-tls')));
    await tester.pump();
    expect(s.repo.settings['verifyTls'], false);
    await tester.enterText(find.byKey(const Key('default-timeout')), '5');
    await tester.pump();
    expect(s.repo.settings['timeoutMs'], 5000);
  });
}
