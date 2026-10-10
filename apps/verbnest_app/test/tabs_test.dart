import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:verbnest_app/src/app.dart';
import 'package:verbnest_app/src/state/editor_state.dart';
import 'package:verbnest_app/src/state/session.dart';
import 'package:verbnest_app/src/state/tree_state.dart';
import 'package:verbnest_core/verbnest_core.dart';

({ProviderContainer c, List<String> ids, String col}) _setup() {
  final s = WorkspaceSession.memory();
  final col = s.repo.createCollection('C');
  final ids = [
    for (final n in ['A', 'B', 'C'])
      s.repo.createRequest(
        col,
        HttpRequestItem(id: '', name: n, url: 'https://x.dev/$n'),
      ),
  ];
  final c = ProviderContainer(
    overrides: [sessionProvider.overrideWithValue(s)],
  );
  addTearDown(() {
    c.dispose();
    s.close();
  });
  return (c: c, ids: ids, col: col);
}

void main() {
  group('preview and pinned tabs', () {
    test('a preview tab is replaced by the next preview', () {
      final t = _setup();
      final tabs = t.c.read(tabsProvider.notifier);
      tabs.open(t.ids[0], preview: true);
      tabs.open(t.ids[1], preview: true);
      final s = t.c.read(tabsProvider);
      expect(s.open, [t.ids[1]]);
      expect(s.preview, t.ids[1]);
      expect(s.active, t.ids[1]);
    });

    test('a pinned tab is kept when a preview opens', () {
      final t = _setup();
      final tabs = t.c.read(tabsProvider.notifier);
      tabs.open(t.ids[0]);
      tabs.open(t.ids[1], preview: true);
      tabs.open(t.ids[2], preview: true);
      expect(t.c.read(tabsProvider).open, [t.ids[0], t.ids[2]]);
      expect(t.c.read(tabsProvider).preview, t.ids[2]);
    });

    test('pinning, opening normally and closing clear the preview', () {
      final t = _setup();
      final tabs = t.c.read(tabsProvider.notifier);
      tabs.open(t.ids[0], preview: true);
      tabs.pin(t.ids[0]);
      expect(t.c.read(tabsProvider).preview, isNull);

      tabs.open(t.ids[1], preview: true);
      tabs.open(t.ids[1]); // opened again without preview
      expect(t.c.read(tabsProvider).preview, isNull);

      tabs.open(t.ids[2], preview: true);
      tabs.close(t.ids[2]);
      expect(t.c.read(tabsProvider).preview, isNull);
    });

    test('editing a preview tab pins it', () async {
      final t = _setup();
      t.c.read(tabsProvider.notifier).open(t.ids[0], preview: true);
      t.c
          .read(editorProvider(t.ids[0]).notifier)
          .edit((i) => i.copyWith(url: 'https://y.dev'));
      expect(t.c.read(tabsProvider).preview, isNull);
      expect(t.c.read(editorProvider(t.ids[0])).dirty, isTrue);
      t.c.read(editorProvider(t.ids[0]).notifier).flush();
      expect(t.c.read(editorProvider(t.ids[0])).dirty, isFalse);
    });

    test('tabs can be reordered', () {
      final t = _setup();
      final tabs = t.c.read(tabsProvider.notifier);
      for (final id in t.ids) {
        tabs.open(id);
      }
      tabs.move(0, 2); // A goes to the end
      expect(t.c.read(tabsProvider).open, [t.ids[1], t.ids[2], t.ids[0]]);
      tabs.move(2, 0);
      expect(t.c.read(tabsProvider).open, t.ids);
      expect(t.c.read(tabsProvider).active, t.ids.last);
    });
  });

  group('tab strip', () {
    Future<({ProviderContainer c, List<String> ids})> pump(
      WidgetTester t,
    ) async {
      t.view.physicalSize = const Size(1280, 800);
      t.view.devicePixelRatio = 1;
      addTearDown(t.view.reset);
      final s = _setup();
      await t.pumpWidget(
        UncontrolledProviderScope(container: s.c, child: const VerbnestApp()),
      );
      await t.pump(const Duration(milliseconds: 300));
      await t.tap(find.byKey(Key('node-${s.col}')));
      await t.pump(const Duration(milliseconds: 300));
      return (c: s.c, ids: s.ids);
    }

    testWidgets('single clicks preview, a double click pins', (t) async {
      final s = await pump(t);
      await t.tap(find.byKey(Key('node-${s.ids[0]}')));
      await t.pump(const Duration(milliseconds: 500));
      await t.tap(find.byKey(Key('node-${s.ids[1]}')));
      await t.pump(const Duration(milliseconds: 500));
      expect(s.c.read(tabsProvider).open, [s.ids[1]]);

      // A second click soon after pins it; the next preview then opens beside.
      await t.tap(find.byKey(Key('node-${s.ids[1]}')));
      await t.pump(const Duration(milliseconds: 100));
      await t.tap(find.byKey(Key('node-${s.ids[1]}')));
      await t.pump(const Duration(milliseconds: 500));
      expect(s.c.read(tabsProvider).preview, isNull);
      await t.tap(find.byKey(Key('node-${s.ids[2]}')));
      await t.pump(const Duration(milliseconds: 500));
      expect(s.c.read(tabsProvider).open, [s.ids[1], s.ids[2]]);
      expect(s.c.read(tabsProvider).preview, s.ids[2]);
    });

    testWidgets('a preview tab is shown in italics', (t) async {
      final s = await pump(t);
      await t.tap(find.byKey(Key('node-${s.ids[0]}')));
      await t.pump(const Duration(milliseconds: 500));
      final title = t.widget<Text>(
        find.descendant(
          of: find.byKey(Key('tab-${s.ids[0]}')),
          matching: find.text('A'),
        ),
      );
      expect(title.style?.fontStyle, FontStyle.italic);
    });

    testWidgets('dragging a tab reorders it', (t) async {
      final s = await pump(t);
      s.c.read(tabsProvider.notifier)
        ..open(s.ids[0])
        ..open(s.ids[1])
        ..open(s.ids[2]);
      await t.pump(const Duration(milliseconds: 300));
      final from = t.getCenter(find.byKey(Key('tab-${s.ids[0]}')));
      final to = t.getCenter(find.byKey(Key('tab-${s.ids[2]}')));
      final g = await t.startGesture(from);
      await t.pump(const Duration(milliseconds: 100));
      // A drag needs several small moves to be recognised.
      final steps = ((to.dx + 60 - from.dx) / 20).ceil();
      for (var i = 0; i < steps; i++) {
        await g.moveBy(const Offset(20, 0));
        await t.pump(const Duration(milliseconds: 30));
      }
      await t.pump(const Duration(milliseconds: 200));
      await g.up();
      await t.pumpAndSettle();
      final open = s.c.read(tabsProvider).open;
      expect(open.first, isNot(s.ids[0]));
      expect(open.last, s.ids[0]);
    });
  });
}
