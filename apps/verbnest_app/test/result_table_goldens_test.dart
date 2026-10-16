import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:verbnest_app/l10n/app_localizations.dart';
import 'package:verbnest_app/src/theme.dart';
import 'package:verbnest_app/src/widgets/result_table_view.dart';
import 'package:verbnest_core/verbnest_core.dart';

import 'support/golden_setup.dart';

/// The results grid, light and dark, sorted by one column, with a null and a
/// nested value. Regenerate with
/// `flutter test --update-goldens test/result_table_goldens_test.dart`.
void main() {
  setUpAll(() async {
    await loadGoldenFonts();
    useTolerantGoldens('test/result_table_goldens_test.dart');
  });

  final table = tableFromJson([
    {
      'id': 1,
      'name': 'Rex',
      'species': 'dog',
      'age': 4,
      'vaccinated': true,
      'owner': null,
      'address': {'city': 'Perth', 'zip': '6000'},
      'seen': '2026-10-02T10:00:00Z',
    },
    {
      'id': 2,
      'name': 'Tom',
      'species': 'cat',
      'age': 2.5,
      'vaccinated': false,
      'owner': 'Ann',
      'address': {'city': 'Hobart'},
      'seen': '2026-09-30',
    },
    {
      'id': 3,
      'name': 'Ziggy, the great',
      'species': 'bird',
      'age': 10,
      'vaccinated': true,
      'owner': 'Bo',
      'address': null,
      'seen': '2026-10-01 08:00',
    },
  ])!;

  for (final brightness in [Brightness.light, Brightness.dark]) {
    testWidgets('results table, ${brightness.name}', (t) async {
      t.view.physicalSize = const Size(900, 320);
      t.view.devicePixelRatio = 1;
      addTearDown(t.view.reset);
      await t.pumpWidget(
        MaterialApp(
          debugShowCheckedModeBanner: false,
          theme: buildTheme(brightness, seed: AppAccents.seed(0)),
          localizationsDelegates: [
            AppLocalizations.delegate,
            ...GlobalMaterialLocalizations.delegates,
          ],
          supportedLocales: AppLocalizations.supportedLocales,
          home: Scaffold(body: ResultTableView(table: table)),
        ),
      );
      await t.pump();
      await t.tap(find.byKey(const ValueKey('table-sort-3')));
      await t.pump();
      await expectLater(
        find.byType(WidgetsApp),
        matchesGoldenFile('goldens/result-table-${brightness.name}.png'),
      );
    });
  }
}
