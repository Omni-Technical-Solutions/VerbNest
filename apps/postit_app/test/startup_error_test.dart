import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:postit_app/main.dart';

void main() {
  testWidgets('startup error screen shows the reason and can retry', (
    tester,
  ) async {
    var retried = 0;
    await tester.pumpWidget(
      StartupErrorApp(message: 'no access', retry: () => retried++),
    );
    expect(find.text('no access'), findsOneWidget);
    await tester.tap(find.text('Try again'));
    expect(retried, 1);
  });
}
