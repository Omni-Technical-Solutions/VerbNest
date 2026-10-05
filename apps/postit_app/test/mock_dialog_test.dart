import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:postit_app/src/state/session.dart';
import 'package:postit_app/src/widgets/mock_server_dialog.dart';
import 'package:postit_core/postit_core.dart';

import 'dart:typed_data';

void main() {
  testWidgets('empty collection explains what to do', (tester) async {
    final s = WorkspaceSession.memory();
    final col = s.repo.createCollection('C');
    await tester.pumpWidget(
      ProviderScope(
        overrides: [sessionProvider.overrideWithValue(s)],
        child: MaterialApp(
          home: Scaffold(body: MockServerDialog(containerId: col)),
        ),
      ),
    );
    expect(find.byKey(const Key('mock-empty')), findsOneWidget);
    expect(find.byKey(const Key('mock-start')), findsNothing);
  });

  testWidgets('lists routes; start and stop toggle', (tester) async {
    final s = WorkspaceSession.memory();
    final col = s.repo.createCollection('C');
    final id = s.repo.createRequest(
      col,
      HttpRequestItem(id: '', name: 'users', url: 'http://x.test/users'),
    );
    s.repo.addExample(id, 'ok', {
      'status': 200,
      'reason': 'OK',
      'headers': <Object>[],
    }, Uint8List(0));
    await tester.pumpWidget(
      ProviderScope(
        overrides: [sessionProvider.overrideWithValue(s)],
        child: MaterialApp(
          home: Scaffold(body: MockServerDialog(containerId: col)),
        ),
      ),
    );
    expect(find.text('GET /users'), findsOneWidget);
    await tester.enterText(find.byKey(const Key('mock-port')), '0');
    await tester.runAsync(() async {
      await tester.tap(find.byKey(const Key('mock-start')));
      await Future<void>.delayed(const Duration(milliseconds: 100));
    });
    await tester.pump();
    expect(find.byKey(const Key('mock-url')), findsOneWidget);
    await tester.runAsync(() async {
      await tester.tap(find.byKey(const Key('mock-stop')));
      await Future<void>.delayed(const Duration(milliseconds: 100));
    });
    await tester.pump();
    expect(find.byKey(const Key('mock-start')), findsOneWidget);
  });
}
