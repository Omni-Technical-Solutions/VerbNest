import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:verbnest_app/l10n/app_localizations.dart';
import 'package:verbnest_app/src/app.dart';
import 'package:verbnest_app/src/state/prefs.dart';
import 'package:verbnest_app/src/state/session.dart';
import 'package:verbnest_app/src/state/tree_state.dart';
import 'package:verbnest_app/src/widgets/request_editor.dart';
import 'package:verbnest_app/src/widgets/ui/adaptive_dialog.dart';
import 'package:verbnest_core/verbnest_core.dart';

Future<ProviderContainer> _pumpApp(WidgetTester t, Size size) async {
  t.view.physicalSize = size;
  t.view.devicePixelRatio = 1;
  addTearDown(t.view.reset);
  final s = WorkspaceSession.memory();
  addTearDown(s.close);
  final col = s.repo.createCollection('Pet Store API');
  s.repo.createRequest(
    col,
    HttpRequestItem(id: '', name: 'List pets', url: 'https://x.dev/pets'),
  );
  final c = ProviderContainer(
    overrides: [sessionProvider.overrideWithValue(s)],
  );
  addTearDown(c.dispose);
  await t.pumpWidget(
    UncontrolledProviderScope(container: c, child: const VerbnestApp()),
  );
  await t.pump(const Duration(milliseconds: 300));
  return c;
}

Future<void> _openPalette(WidgetTester t) async {
  await t.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
  await t.sendKeyEvent(LogicalKeyboardKey.keyK);
  await t.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
  await t.pump(const Duration(milliseconds: 400));
}

void main() {
  group('dialogs follow the window size class', () {
    testWidgets('the command palette is full screen on a phone', (t) async {
      await _pumpApp(t, const Size(402, 874));
      await _openPalette(t);
      final input = find.byKey(const Key('palette-input'));
      expect(input, findsOneWidget);
      // Edge to edge, at the top of the window.
      expect(t.getSize(input).width, greaterThan(370));
      expect(t.getTopLeft(input).dy, lessThan(60));
      expect(t.takeException(), isNull);
    });

    testWidgets('the command palette is a box near the top on desktop', (
      t,
    ) async {
      await _pumpApp(t, const Size(1280, 800));
      await _openPalette(t);
      final input = find.byKey(const Key('palette-input'));
      expect(t.getSize(input).width, lessThanOrEqualTo(560));
      expect(t.getTopLeft(input).dy, greaterThan(80));
      expect(t.getTopLeft(input).dx, greaterThan(300));
    });

    testWidgets('a titled dialog has a close button when full screen', (
      t,
    ) async {
      t.view.physicalSize = const Size(402, 874);
      t.view.devicePixelRatio = 1;
      addTearDown(t.view.reset);
      await t.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (context) => TextButton(
              onPressed: () => showDialog<void>(
                context: context,
                builder: (_) => const AdaptiveDialog(
                  title: 'Generate code',
                  content: Text('body'),
                  actions: [TextButton(onPressed: null, child: Text('Copy'))],
                ),
              ),
              child: const Text('open'),
            ),
          ),
        ),
      );
      await t.tap(find.text('open'));
      await t.pump(const Duration(milliseconds: 400));
      expect(find.byType(CloseButton), findsOneWidget);
      expect(find.byType(AlertDialog), findsNothing);
      expect(find.text('Copy'), findsOneWidget);
      await t.tap(find.byType(CloseButton));
      await t.pump(const Duration(milliseconds: 400));
      expect(find.text('Generate code'), findsNothing);
    });

    testWidgets('a titled dialog is an alert dialog on a wide window', (
      t,
    ) async {
      t.view.physicalSize = const Size(1000, 800);
      t.view.devicePixelRatio = 1;
      addTearDown(t.view.reset);
      await t.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (context) => TextButton(
              onPressed: () => showDialog<void>(
                context: context,
                builder: (_) => const AdaptiveDialog(
                  title: 'Generate code',
                  content: Text('body'),
                ),
              ),
              child: const Text('open'),
            ),
          ),
        ),
      );
      await t.tap(find.text('open'));
      await t.pump(const Duration(milliseconds: 400));
      expect(find.byType(AlertDialog), findsOneWidget);
      expect(find.byType(CloseButton), findsNothing);
    });
  });

  group('request and response panes', () {
    Future<ProviderContainer> pumpEditor(WidgetTester t, Size size) async {
      t.view.physicalSize = size;
      t.view.devicePixelRatio = 1;
      addTearDown(t.view.reset);
      final s = WorkspaceSession.memory();
      addTearDown(s.close);
      final col = s.repo.createCollection('C');
      final id = s.repo.createRequest(
        col,
        HttpRequestItem(id: '', name: 'R', url: 'https://x.dev'),
      );
      final c = ProviderContainer(
        overrides: [sessionProvider.overrideWithValue(s)],
      );
      addTearDown(c.dispose);
      await t.pumpWidget(
        UncontrolledProviderScope(
          container: c,
          child: MaterialApp(
            localizationsDelegates: [
              AppLocalizations.delegate,
              ...GlobalMaterialLocalizations.delegates,
            ],
            supportedLocales: AppLocalizations.supportedLocales,
            home: Scaffold(body: RequestEditor(requestId: id)),
          ),
        ),
      );
      await t.pump(const Duration(milliseconds: 300));
      return c;
    }

    testWidgets('a wide editor puts the response beside the request', (
      t,
    ) async {
      await pumpEditor(t, const Size(1500, 900));
      final request = t.getTopLeft(find.byKey(const Key('url')));
      final response = t.getTopLeft(
        find.text('Send the request to see a response'),
      );
      expect(response.dx, greaterThan(request.dx + 400));
    });

    testWidgets('a medium editor stacks them', (t) async {
      await pumpEditor(t, const Size(900, 900));
      final request = t.getTopLeft(find.byKey(const Key('url')));
      final response = t.getTopLeft(
        find.text('Send the request to see a response'),
      );
      expect(response.dy, greaterThan(request.dy + 100));
    });

    testWidgets('the saved direction beats the width', (t) async {
      final c = await pumpEditor(t, const Size(1500, 900));
      c
          .read(splitLayoutProvider.notifier)
          .update(const SplitLayout(horizontal: false));
      await t.pump(const Duration(milliseconds: 300));
      final request = t.getTopLeft(find.byKey(const Key('url')));
      final response = t.getTopLeft(
        find.text('Send the request to see a response'),
      );
      expect(response.dy, greaterThan(request.dy + 100));
    });
  });

  testWidgets('tablet portrait width shows the list beside the editor', (
    t,
  ) async {
    final c = await _pumpApp(t, const Size(840, 1000));
    expect(find.byKey(const Key('layout-expanded')), findsOneWidget);
    final id = c.read(repositoryProvider).children(null).first.id;
    expect(id, isNotEmpty);
    expect(find.byKey(const Key('sidebar-filter')), findsOneWidget);
    c
        .read(tabsProvider.notifier)
        .open(
          c
              .read(repositoryProvider)
              .searchDocuments()
              .firstWhere((d) => d.kind.name == 'request')
              .id,
        );
    await t.pump(const Duration(milliseconds: 400));
    expect(find.byKey(const Key('url')), findsOneWidget);
    expect(find.byKey(const Key('sidebar-filter')), findsOneWidget);
  });

  group('navigation drawer on large windows', () {
    testWidgets('large windows have a permanent drawer, not a rail', (t) async {
      await _pumpApp(t, const Size(1200, 800));
      expect(find.byKey(const Key('nav-drawer')), findsOneWidget);
      expect(find.byType(NavigationDrawer), findsOneWidget);
      expect(find.byType(NavigationRail), findsNothing);
      expect(find.text('VerbNest'), findsOneWidget);
      for (final label in [
        'Collections',
        'History',
        'Environments',
        'Settings',
      ]) {
        expect(
          find.descendant(
            of: find.byType(NavigationDrawer),
            matching: find.text(label),
          ),
          findsOneWidget,
        );
      }
      // The sidebar and editor still fit beside it.
      expect(find.byKey(const Key('sidebar-filter')), findsOneWidget);
      expect(t.takeException(), isNull);
    });

    testWidgets('expanded windows keep the rail', (t) async {
      await _pumpApp(t, const Size(1199, 800));
      expect(find.byType(NavigationRail), findsOneWidget);
      expect(find.byType(NavigationDrawer), findsNothing);
      expect(find.byKey(const Key('layout-expanded')), findsOneWidget);
    });

    testWidgets('choosing a destination in the drawer changes the page', (
      t,
    ) async {
      await _pumpApp(t, const Size(1440, 900));
      await t.tap(
        find.descendant(
          of: find.byType(NavigationDrawer),
          matching: find.text('Settings'),
        ),
      );
      await t.pump(const Duration(milliseconds: 500));
      expect(find.text('Verify TLS certificates'), findsOneWidget);
      expect(find.byKey(const Key('sidebar-filter')), findsNothing);
    });

    testWidgets('the drawer is on the right in right-to-left', (t) async {
      t.platformDispatcher.localesTestValue = const [Locale('ar')];
      addTearDown(t.platformDispatcher.clearLocalesTestValue);
      await _pumpApp(t, const Size(1440, 900));
      await t.pumpAndSettle();
      expect(
        t.getTopRight(find.byKey(const Key('nav-drawer'))).dx,
        closeTo(1440, 1),
      );
    });
  });
}
