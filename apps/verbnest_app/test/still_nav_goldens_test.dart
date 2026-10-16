import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:verbnest_app/src/theme.dart';
import 'package:verbnest_app/src/widgets/ui/still_nav.dart';
import 'package:verbnest_app/src/widgets/ui/still_tabs.dart';

import 'support/golden_setup.dart';

/// The navigation bar, rail and drawer, and a tab bar, which replace Material's
/// animated ones. Regenerate with
/// `flutter test --update-goldens test/still_nav_goldens_test.dart`.
void main() {
  setUpAll(() async {
    await loadGoldenFonts();
    useTolerantGoldens('test/still_nav_goldens_test.dart');
  });

  const items = [
    StillDestination(
      icon: Icons.folder_outlined,
      selectedIcon: Icons.folder,
      label: 'Collections',
    ),
    StillDestination(
      icon: Icons.history,
      selectedIcon: Icons.history,
      label: 'History',
    ),
    StillDestination(
      icon: Icons.tune_outlined,
      selectedIcon: Icons.tune,
      label: 'Environments',
    ),
    StillDestination(
      icon: Icons.settings_outlined,
      selectedIcon: Icons.settings,
      label: 'Settings',
    ),
  ];

  for (final brightness in Brightness.values) {
    testWidgets('still navigation, ${brightness.name}', (t) async {
      t.view.physicalSize = const Size(900, 420);
      t.view.devicePixelRatio = 1;
      addTearDown(t.view.reset);
      await t.pumpWidget(
        MaterialApp(
          debugShowCheckedModeBanner: false,
          theme: buildTheme(brightness, seed: AppAccents.seed(0)),
          home: DefaultTabController(
            length: 4,
            child: Scaffold(
              body: Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  StillNavigationRail(
                    destinations: items,
                    selectedIndex: 1,
                    onDestinationSelected: (_) {},
                  ),
                  SizedBox(
                    width: 240,
                    child: StillNavigationDrawer(
                      header: const Padding(
                        padding: EdgeInsets.all(24),
                        child: Text('VerbNest'),
                      ),
                      destinations: items,
                      selectedIndex: 0,
                      onDestinationSelected: (_) {},
                    ),
                  ),
                  Expanded(
                    child: Column(
                      children: [
                        const StillTabBar(
                          isScrollable: true,
                          tabs: [
                            Tab(text: 'Params'),
                            Tab(text: 'Headers'),
                            Tab(text: 'Auth'),
                            Tab(text: 'Body'),
                          ],
                        ),
                        const StillTabBar(
                          secondary: true,
                          tabs: [
                            Tab(text: 'Body'),
                            Tab(text: 'Cookies'),
                            Tab(text: 'Headers'),
                            Tab(text: 'Tests'),
                          ],
                        ),
                        const Spacer(),
                        StillNavigationBar(
                          destinations: items,
                          selectedIndex: 2,
                          onDestinationSelected: (_) {},
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      );
      await t.pump();
      await expectLater(
        find.byType(WidgetsApp),
        matchesGoldenFile('goldens/still-nav-${brightness.name}.png'),
      );
    });
  }
}
