import 'package:material_ui/material_ui.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:verbnest_app/src/theme.dart';
import 'package:verbnest_app/src/widgets/ui/ui.dart';

/// Golden shots of the shared kit in both themes. The test font is Ahem, so
/// these guard colour and layout, not glyph shapes. Regenerate with
/// `flutter test --update-goldens`.
void main() {
  Future<void> shot(
    WidgetTester tester,
    String name,
    Widget child,
    Brightness brightness,
  ) async {
    tester.view.physicalSize = const Size(620, 460);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MaterialApp(
        debugShowCheckedModeBanner: false,
        theme: buildTheme(brightness),
        home: Scaffold(body: Center(child: child)),
      ),
    );
    await tester.pump();
    await expectLater(
      find.byType(MaterialApp),
      matchesGoldenFile('goldens/$name.png'),
    );
  }

  Widget kit() => const Column(
    mainAxisSize: MainAxisSize.min,
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Wrap(
        spacing: 8,
        runSpacing: 8,
        children: [
          MethodBadge('GET'),
          MethodBadge('POST'),
          MethodBadge('DELETE'),
          StatusPill(200, '200 OK'),
          StatusPill(404, '404 Not Found'),
          CountBadge(7),
          Kbd('Ctrl+K'),
        ],
      ),
      SizedBox(height: 8),
      InlineBanner(tone: BannerTone.warning, child: Text('Heads up')),
      SizedBox(height: 8),
      SizedBox(
        width: 320,
        child: EmptyState(
          icon: Icons.bolt_outlined,
          title: 'Send the request to see a response',
          hint: 'Ctrl+Enter',
        ),
      ),
    ],
  );

  testWidgets(
    'ui kit, light',
    (tester) => shot(tester, 'kit-light', kit(), Brightness.light),
  );
  testWidgets(
    'ui kit, dark',
    (tester) => shot(tester, 'kit-dark', kit(), Brightness.dark),
  );
}
