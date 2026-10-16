import 'package:flutter/foundation.dart'
    show TargetPlatform, debugDefaultTargetPlatformOverride;
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:verbnest_app/l10n/app_localizations.dart';
import 'package:verbnest_app/src/theme.dart';
import 'package:verbnest_app/src/widgets/result_table_view.dart';
import 'package:verbnest_core/verbnest_core.dart';

ResultTable table() => tableFromJson([
  {'id': 1, 'name': 'Rex', 'age': 4, 'owner': null},
  {'id': 2, 'name': 'Tom', 'age': 2.5, 'owner': 'Ann'},
  {'id': 3, 'name': 'Ann', 'age': 10, 'owner': 'Bo'},
])!;

Future<void> pumpTable(
  WidgetTester t, {
  Brightness brightness = Brightness.light,
  Size size = const Size(402, 800),
  double textScale = 1,
}) async {
  t.view.physicalSize = size;
  t.view.devicePixelRatio = 1;
  addTearDown(t.view.reset);
  await t.pumpWidget(
    MaterialApp(
      theme: buildTheme(brightness, seed: AppAccents.seed(0)),
      localizationsDelegates: [
        AppLocalizations.delegate,
        ...GlobalMaterialLocalizations.delegates,
      ],
      supportedLocales: AppLocalizations.supportedLocales,
      home: MediaQuery(
        data: MediaQueryData(
          size: size,
          textScaler: TextScaler.linear(textScale),
        ),
        child: Scaffold(body: ResultTableView(table: table())),
      ),
    ),
  );
  await t.pump();
}

void main() {
  testWidgets('cells say their column, row, total and value', (t) async {
    final h = t.ensureSemantics();
    await pumpTable(t);
    expect(find.bySemanticsLabel('name, row 1 of 3: Rex'), findsOneWidget);
    expect(find.bySemanticsLabel('age, row 2 of 3: 2.5'), findsOneWidget);
    // A null is spoken as "null", not as nothing.
    expect(find.bySemanticsLabel('owner, row 1 of 3: null'), findsOneWidget);
    expect(find.bySemanticsLabel('Row 2'), findsOneWidget);
    expect(find.bySemanticsLabel('name, text'), findsOneWidget);
    h.dispose();
  });

  testWidgets('the header says how it is sorted', (t) async {
    final h = t.ensureSemantics();
    await pumpTable(t);
    expect(t.getSemantics(find.bySemanticsLabel('age, number')).value, '');
    await t.tap(find.byKey(const ValueKey('table-sort-2')));
    await t.pump();
    expect(
      t.getSemantics(find.bySemanticsLabel('age, number')).value,
      'sorted ascending',
    );
    await t.tap(find.byKey(const ValueKey('table-sort-2')));
    await t.pump();
    expect(
      t.getSemantics(find.bySemanticsLabel('age, number')).value,
      'sorted descending',
    );
    h.dispose();
  });

  testWidgets('a screen reader can activate a cell and a row number', (
    t,
  ) async {
    final h = t.ensureSemantics();
    await pumpTable(t, size: const Size(800, 800));
    // Activating a cell opens its value in full.
    t.semantics.tap(find.semantics.byLabel('name, row 1 of 3: Rex'));
    await t.pumpAndSettle();
    expect(find.byKey(const Key('table-value')), findsOneWidget);
    await t.tap(find.text('Close'));
    await t.pumpAndSettle();
    // Activating a row number selects the row; the cells report it.
    t.semantics.tap(find.semantics.byLabel('Row 2'));
    await t.pump();
    expect(
      t.getSemantics(find.bySemanticsLabel('name, row 2 of 3: Tom')),
      isSemantics(isSelected: true, hasSelectedState: true),
    );
    expect(
      t.getSemantics(find.bySemanticsLabel('name, row 1 of 3: Rex')),
      isSemantics(isSelected: false, hasSelectedState: true),
    );
    h.dispose();
  });

  testWidgets('the 12 dp resize handle is not in the accessibility tree', (
    t,
  ) async {
    final h = t.ensureSemantics();
    await pumpTable(t);
    expect(find.bySemanticsLabel(RegExp('^Resize')), findsNothing);
    h.dispose();
  });

  // The 48 dp target rule is for touch devices, which get 48 dp rows and a
  // 56 dp header; a desktop uses compact rows.
  for (final platform in [TargetPlatform.android, TargetPlatform.iOS]) {
    for (final brightness in Brightness.values) {
      testWidgets('meets the guidelines, ${platform.name} ${brightness.name}', (
        t,
      ) async {
        debugDefaultTargetPlatformOverride = platform;
        final h = t.ensureSemantics();
        try {
          await pumpTable(t, brightness: brightness);
          await expectLater(t, meetsGuideline(textContrastGuideline));
          await expectLater(t, meetsGuideline(labeledTapTargetGuideline));
          if (platform == TargetPlatform.android) {
            await expectLater(t, meetsGuideline(androidTapTargetGuideline));
          } else {
            await expectLater(t, meetsGuideline(iOSTapTargetGuideline));
          }
        } finally {
          h.dispose();
          debugDefaultTargetPlatformOverride = null;
        }
      });
    }
  }

  testWidgets('large text grows the rows instead of cutting values', (t) async {
    await pumpTable(t, textScale: 2);
    final one = t.getSize(find.byKey(const ValueKey('table-row-0'))).height;
    await pumpTable(t, textScale: 1);
    final normal = t.getSize(find.byKey(const ValueKey('table-row-0'))).height;
    expect(one, greaterThan(normal));
  });
}
