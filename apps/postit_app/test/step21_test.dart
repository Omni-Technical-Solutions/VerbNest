import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:postit_app/src/state/import_actions.dart';
import 'package:postit_app/src/state/session.dart';
import 'package:postit_app/src/widgets/code_dialog.dart';

void main() {
  testWidgets('code dialog switches language and fills in variables', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1000, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final s = WorkspaceSession.memory();
    addTearDown(s.close);
    final id = importText(s, 'curl https://a.test/x').nodeId!;
    await tester.pumpWidget(
      ProviderScope(
        overrides: [sessionProvider.overrideWithValue(s)],
        child: MaterialApp(
          home: Scaffold(body: CodeDialog(requestId: id)),
        ),
      ),
    );
    String code() =>
        tester.widget<SelectableText>(find.byKey(const Key('code-text'))).data!;
    expect(code(), startsWith('curl'));
    await tester.tap(find.byKey(const Key('code-language')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Python (requests)').last);
    await tester.pumpAndSettle();
    expect(code(), contains('import requests'));
    await tester.tap(find.byKey(const Key('code-resolve')));
    await tester.pump();
    expect(code(), contains('https://a.test/x'));
  });
}
