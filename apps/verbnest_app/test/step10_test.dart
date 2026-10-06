import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:verbnest_app/src/pages/environments_page.dart';
import 'package:verbnest_app/src/settings_page.dart';
import 'package:verbnest_app/src/state/session.dart';
import 'package:verbnest_app/src/state/variables.dart';
import 'package:verbnest_core/verbnest_core.dart';
import 'package:verbnest_storage/verbnest_storage.dart';

void main() {
  test('current value overrides the initial value only when resolving', () {
    final s = WorkspaceSession.memory();
    addTearDown(s.close);
    final owner = VariableOwner.environment('E');
    s.repo.saveEnvironment(const Environment(id: 'E', name: 'Dev'));
    saveVariables(
      s,
      owner,
      [
        const Variable(key: 'host', value: 'shared.test'),
        const Variable(key: 'other', value: 'x'),
      ],
      current: {'host': 'mine.test'},
    );
    expect(s.repo.variables(owner).first.value, 'shared.test');
    expect(loadVariables(s, owner).first.value, 'shared.test');
    expect(loadResolvedVariables(s, owner).first.value, 'mine.test');
    expect(loadResolvedVariables(s, owner).last.value, 'x');

    // Removing the variable drops its override.
    saveVariables(s, owner, [
      const Variable(key: 'other', value: 'x'),
    ], current: {});
    expect(loadCurrentValues(s, owner), isEmpty);
  });

  test('collection secrets resolve in request scopes', () {
    final s = WorkspaceSession.memory();
    addTearDown(s.close);
    final col = s.repo.createCollection('C');
    final id = s.repo.createRequest(col, HttpRequestItem(id: '', name: 'R'));
    saveVariables(s, VariableOwner.collection(col), [
      const Variable(key: 'tok', value: 'abc', secret: true),
    ]);
    final scopes = buildScopes(s, requestId: id);
    expect(scopes.lookup('tok')!.variable.value, 'abc');
  });

  testWidgets('secret value can be revealed and plain rows show current', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: VariablesEditor(
            initial: const [
              Variable(key: 'a', value: '1'),
              Variable(key: 's', value: 'hush', secret: true),
            ],
            initialCurrent: const {'a': '2'},
            onChanged: (_, _) {},
          ),
        ),
      ),
    );
    EditableText field(String key) => tester.widget<EditableText>(
      find.descendant(
        of: find.byKey(ValueKey(key)),
        matching: find.byType(EditableText),
      ),
    );
    expect(field('var-value-1-true').obscureText, isTrue);
    await tester.tap(find.byKey(const ValueKey('var-reveal-1')));
    await tester.pump();
    expect(field('var-value-1-true-shown').obscureText, isFalse);
    expect(find.text('2'), findsOneWidget);
  });

  testWidgets('settings tell when secrets are unprotected', (tester) async {
    final s = WorkspaceSession.memory();
    addTearDown(s.close);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [sessionProvider.overrideWithValue(s)],
        child: const MaterialApp(home: Scaffold(body: SettingsPage())),
      ),
    );
    expect(find.textContaining('unencrypted'), findsOneWidget);
  });
}
