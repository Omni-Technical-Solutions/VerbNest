import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:verbnest_app/src/state/code_view.dart';
import 'package:verbnest_app/src/state/prefs.dart';
import 'package:verbnest_app/src/state/session.dart';
import 'package:verbnest_app/src/theme.dart';
import 'package:verbnest_app/src/widgets/ui/split_view.dart';
import 'package:verbnest_app/src/widgets/ui/ui.dart';

Widget _host(Widget child, {Brightness b = Brightness.light}) => MaterialApp(
  theme: buildTheme(b),
  home: Scaffold(body: child),
);

void main() {
  test('status and method colours follow meaning', () {
    const c = AppColors.light;
    expect(c.status(200), c.success);
    expect(c.status(301), c.info);
    expect(c.status(404), c.warning);
    expect(c.status(503), c.danger);
    expect(c.method('post'), c.post);
    expect(c.method('TRACE'), c.otherMethod);
    expect(AppColors.light.get, isNot(AppColors.dark.get));
  });

  testWidgets('theme registers colours for both brightnesses', (tester) async {
    for (final b in Brightness.values) {
      late AppColors seen;
      await tester.pumpWidget(
        _host(
          Builder(
            builder: (context) {
              seen = AppColors.of(context);
              return const SizedBox();
            },
          ),
          b: b,
        ),
      );
      await tester.pumpAndSettle();
      expect(seen, b == Brightness.dark ? AppColors.dark : AppColors.light);
    }
  });

  testWidgets('split view drag reports a new ratio', (tester) async {
    double? ratio;
    await tester.pumpWidget(
      _host(
        SplitView(
          axis: Axis.vertical,
          ratio: 0.5,
          onRatioChanged: (r) => ratio = r,
          first: const Text('a'),
          second: const Text('b'),
        ),
      ),
    );
    await tester.drag(
      find.byKey(const Key('split-handle')),
      const Offset(0, 60),
    );
    expect(ratio, isNotNull);
    expect(ratio, greaterThan(0.5));
  });

  testWidgets('empty state, badges and banner render', (tester) async {
    await tester.pumpWidget(
      _host(
        const Column(
          children: [
            EmptyState(icon: Icons.http, title: 'Nothing', hint: 'Try this'),
            CountBadge(3),
            MethodBadge('DELETE'),
            InlineBanner(tone: BannerTone.warning, child: Text('Heads up')),
            Kbd('Ctrl+K'),
          ],
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Nothing'), findsOneWidget);
    expect(find.text('Try this'), findsOneWidget);
    expect(find.text('3'), findsOneWidget);
    expect(find.text('DEL'), findsOneWidget);
    expect(find.text('Heads up'), findsOneWidget);
    expect(find.text('Ctrl+K'), findsOneWidget);
  });

  testWidgets('reduced motion zeroes durations', (tester) async {
    late Duration d;
    await tester.pumpWidget(
      MediaQuery(
        data: const MediaQueryData(disableAnimations: true),
        child: Builder(
          builder: (context) {
            d = Motion.of(context, Motion.base);
            return const SizedBox();
          },
        ),
      ),
    );
    expect(d, Duration.zero);
  });

  test('accent and density change the theme and persist as preferences', () {
    final orange = buildTheme(Brightness.light);
    final blue = buildTheme(
      Brightness.light,
      seed: AppAccents.seed(1),
      compact: true,
    );
    expect(blue.colorScheme.primary, isNot(orange.colorScheme.primary));
    expect(blue.visualDensity, VisualDensity.compact);
    expect(AppAccents.seed(99), AppAccents.seeds.first);

    final s = WorkspaceSession.memory();
    addTearDown(s.close);
    final c = ProviderContainer(
      overrides: [sessionProvider.overrideWithValue(s)],
    );
    addTearDown(c.dispose);
    final n = c.read(prefsProvider.notifier);
    n.update(c.read(prefsProvider).copyWith(accent: 2, compact: true));
    c.invalidate(prefsProvider);
    expect(c.read(prefsProvider).accent, 2);
    expect(c.read(prefsProvider).compact, isTrue);
  });

  test('jsonPathForLine names the value on each line', () {
    final lines = [
      '{',
      '  "name": "x",',
      '  "items": [',
      '    {',
      '      "id": 1,',
      '      "tags": [',
      '        "a",',
      '        "b"',
      '      ]',
      '    },',
      '    2',
      '  ],',
      '  "my key": {',
      '    "q": null',
      '  }',
      '}',
    ];
    String? at(int i) => jsonPathForLine(lines, i);
    expect(at(0), r'$');
    expect(at(1), r'$.name');
    expect(at(2), r'$.items');
    expect(at(3), r'$.items[0]');
    expect(at(4), r'$.items[0].id');
    expect(at(6), r'$.items[0].tags[0]');
    expect(at(7), r'$.items[0].tags[1]');
    expect(at(8), r'$.items[0].tags');
    expect(at(10), r'$.items[1]');
    expect(at(13), r"$['my key'].q");
    expect(at(99), isNull);
  });
}
