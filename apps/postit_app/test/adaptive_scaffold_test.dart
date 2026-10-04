import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:postit_app/src/app.dart';
import 'package:postit_app/src/layout_class.dart';

Future<void> pumpAt(WidgetTester tester, Size size) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(const PostItApp());
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
  });

  testWidgets('tablet width uses a rail without sidebar', (tester) async {
    await pumpAt(tester, const Size(800, 1024));
    expect(find.byKey(const Key('layout-medium')), findsOneWidget);
    expect(find.byType(NavigationRail), findsOneWidget);
    expect(find.text('Collections sidebar'), findsNothing);
  });

  testWidgets('desktop width shows rail and sidebar', (tester) async {
    await pumpAt(tester, const Size(1400, 900));
    expect(find.byKey(const Key('layout-expanded')), findsOneWidget);
    expect(find.text('Collections sidebar'), findsOneWidget);
  });

  testWidgets('navigating to settings shows the stub page', (tester) async {
    await pumpAt(tester, const Size(1400, 900));
    await tester.tap(find.text('Settings'));
    await tester.pump();
    expect(find.text('Verify TLS certificates'), findsOneWidget);
  });
}
