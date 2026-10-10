import 'package:material_ui/material_ui.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:verbnest_app/src/app.dart';
import 'package:verbnest_app/src/layout_class.dart';
import 'package:verbnest_app/src/adaptive_scaffold.dart';
import 'package:verbnest_app/src/state/session.dart';
import 'package:verbnest_app/src/state/tree_state.dart';
import 'package:verbnest_core/verbnest_core.dart';

Future<WorkspaceSession> pumpAt(WidgetTester tester, Size size) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  final session = WorkspaceSession.memory();
  addTearDown(session.close);
  await tester.pumpWidget(
    ProviderScope(
      overrides: [sessionProvider.overrideWithValue(session)],
      child: const VerbnestApp(),
    ),
  );
  return session;
}

void main() {
  test('layout class breakpoints', () {
    expect(LayoutClass.forWidth(599), LayoutClass.compact);
    expect(LayoutClass.forWidth(600), LayoutClass.medium);
    expect(LayoutClass.forWidth(1023), LayoutClass.medium);
    expect(LayoutClass.forWidth(1024), LayoutClass.expanded);
  });

  testWidgets('phone width uses a bottom navigation bar', (tester) async {
    await pumpAt(tester, const Size(390, 844));
    expect(find.byKey(const Key('layout-compact')), findsOneWidget);
    expect(find.byType(NavigationBar), findsOneWidget);
    expect(find.byType(NavigationRail), findsNothing);
    expect(find.byKey(const Key('sidebar-filter')), findsOneWidget);
  });

  testWidgets('tablet width uses a rail with the tree as content', (
    tester,
  ) async {
    await pumpAt(tester, const Size(800, 1024));
    expect(find.byKey(const Key('layout-medium')), findsOneWidget);
    expect(find.byType(NavigationRail), findsOneWidget);
    expect(find.byKey(const Key('sidebar-filter')), findsOneWidget);
  });

  testWidgets('desktop width shows rail and sidebar', (tester) async {
    await pumpAt(tester, const Size(1400, 900));
    expect(find.byKey(const Key('layout-expanded')), findsOneWidget);
    expect(find.byKey(const Key('sidebar-filter')), findsOneWidget);
    expect(find.text('Select or create a request'), findsOneWidget);
  });

  testWidgets('navigating to settings shows the stub page', (tester) async {
    await pumpAt(tester, const Size(1400, 900));
    await tester.tap(find.text('Settings'));
    await tester.pump();
    expect(find.text('Verify TLS certificates'), findsOneWidget);
  });

  testWidgets('creating a collection and request shows them in the tree', (
    tester,
  ) async {
    final session = await pumpAt(tester, const Size(1400, 900));
    await tester.tap(find.byKey(const Key('new-collection')));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField).last, 'Users');
    await tester.tap(find.text('Create'));
    await tester.pumpAndSettle();
    expect(find.text('Users'), findsOneWidget);

    final id = session.repo.children(null).single.id;
    await tester.tap(find.byKey(Key('menu-$id')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('New request'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField).last, 'List users');
    await tester.tap(find.text('Create'));
    await tester.pumpAndSettle();
    expect(find.text('List users'), findsWidgets);
    expect(session.repo.children(id).single.name, 'List users');
  });

  testWidgets('ctrl+W closes the active tab', (tester) async {
    final session = await pumpAt(tester, const Size(1400, 900));
    final c = session.repo.createCollection('C');
    final id = session.repo.createRequest(
      c,
      HttpRequestItem(id: '', name: 'R'),
    );
    final container = ProviderScope.containerOf(
      tester.element(find.byType(AdaptiveScaffold)),
    );
    container.read(tabsProvider.notifier).open(id);
    await tester.pump();
    expect(container.read(tabsProvider).open, [id]);
    await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.keyW);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
    await tester.pump();
    expect(container.read(tabsProvider).open, isEmpty);
  });
}
