
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:postit_app/src/app.dart';
import 'package:postit_app/src/pages/command_palette.dart';
import 'package:postit_app/src/state/folder_port.dart';
import 'package:postit_app/src/state/session.dart';
import 'package:postit_app/src/widgets/collections_sidebar.dart';
import 'package:postit_app/src/widgets/request_extras.dart';
import 'package:postit_core/postit_core.dart';
import 'package:postit_import/postit_import.dart';

Future<WorkspaceSession> pumpApp(WidgetTester tester, Size size) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  final s = WorkspaceSession.memory();
  addTearDown(s.close);
  await tester.pumpWidget(
    ProviderScope(
      overrides: [sessionProvider.overrideWithValue(s)],
      child: const PostItApp(),
    ),
  );
  return s;
}

void main() {
  test('palette filter ranks prefix matches first and needs every word', () {
    PaletteEntry e(String t, [String? sub]) =>
        PaletteEntry(id: t, title: t, subtitle: sub, run: () {});
    final all = [
      e('Get users', 'GET https://a.test/users'),
      e('Send request'),
      e('Create user'),
      e('Users list'),
    ];
    expect(filterPalette(all, '').length, 4);
    expect(filterPalette(all, 'user').map((x) => x.title), [
      'Users list',
      'Get users',
      'Create user',
    ]);
    expect(filterPalette(all, 'get a.test').map((x) => x.title), ['Get users']);
    expect(filterPalette(all, 'zzz'), isEmpty);
  });

  testWidgets('palette: type, arrow, enter runs the entry', (tester) async {
    var ran = '';
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => TextButton(
            onPressed: () => showCommandPalette(context, [
              PaletteEntry(id: 'a', title: 'Alpha', run: () => ran = 'a'),
              PaletteEntry(id: 'b', title: 'Beta one', run: () => ran = 'b'),
              PaletteEntry(id: 'c', title: 'Beta two', run: () => ran = 'c'),
            ]),
            child: const Text('open'),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const Key('palette-input')), 'beta');
    await tester.pump();
    expect(find.byKey(const Key('palette-a')), findsNothing);
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    await tester.pump();
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pumpAndSettle();
    expect(ran, 'c');

    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const Key('palette-input')), 'nope');
    await tester.pump();
    expect(find.byKey(const Key('palette-empty')), findsOneWidget);
  });

  testWidgets('Ctrl+K opens the palette and lists requests', (tester) async {
    final s = await pumpApp(tester, const Size(1200, 900));
    final c = s.repo.createCollection('C');
    s.repo.createRequest(
      c,
      const HttpRequestItem(id: '', name: 'Fetch users', url: 'http://u.test'),
    );
    await tester.pumpAndSettle();
    await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.keyK);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('palette-input')), findsOneWidget);
    await tester.enterText(find.byKey(const Key('palette-input')), 'fetch');
    await tester.pump();
    final hit = find.textContaining('Fetch users');
    expect(hit, findsWidgets);
    await tester.tap(hit.first);
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('palette-input')), findsNothing);
    expect(find.byKey(const Key('favourite')), findsOneWidget);
  });

  testWidgets('Arabic locale: translated labels and right-to-left layout', (
    tester,
  ) async {
    tester.platformDispatcher.localesTestValue = const [Locale('ar')];
    addTearDown(tester.platformDispatcher.clearLocalesTestValue);
    await pumpApp(tester, const Size(1200, 900));
    await tester.pumpAndSettle();
    expect(find.text('المجموعات'), findsWidgets);
    expect(find.text('الإعدادات'), findsWidgets);
    final dir = Directionality.of(tester.element(find.byType(NavigationRail)));
    expect(dir, TextDirection.rtl);
    // The rail sits on the right edge in right-to-left.
    final rail = tester.getTopRight(find.byType(NavigationRail));
    expect(rail.dx, closeTo(1200, 1));
    expect(tester.takeException(), isNull);
  });

  testWidgets('favourites: star in the editor, mark in the tree, filter', (
    tester,
  ) async {
    final s = await pumpApp(tester, const Size(1200, 900));
    final c = s.repo.createCollection('C');
    final a = s.repo.createRequest(
      c,
      const HttpRequestItem(id: '', name: 'Alpha'),
    );
    s.repo.createRequest(c, const HttpRequestItem(id: '', name: 'Beta'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(Key('node-$c')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(Key('node-$a')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('favourite')));
    await tester.pumpAndSettle();
    expect(s.repo.favourites(), [a]);
    expect(find.byKey(Key('fav-$a')), findsOneWidget);

    await tester.tap(find.byKey(const Key('favourites-filter')));
    await tester.pumpAndSettle();
    expect(find.byKey(Key('node-$a')), findsWidgets);
    expect(find.text('Beta'), findsNothing);
    expect(find.byType(CollectionsSidebar), findsOneWidget);
  });

  testWidgets('examples: save the response, read it back, delete it', (
    tester,
  ) async {
    final s = WorkspaceSession.memory();
    addTearDown(s.close);
    final c = s.repo.createCollection('C');
    final r = s.repo.createRequest(
      c,
      const HttpRequestItem(id: '', name: 'R', url: 'http://h.test/x'),
    );
    final id = s.repo.addExample(r, '200 OK', {
      'status': 200,
      'reason': 'OK',
      'headers': [
        ['Content-Type', 'text/plain'],
      ],
    }, Uint8List.fromList('hello'.codeUnits));
    await tester.pumpWidget(
      ProviderScope(
        overrides: [sessionProvider.overrideWithValue(s)],
        child: MaterialApp(
          home: Scaffold(body: ExamplesDialog(requestId: r)),
        ),
      ),
    );
    expect(find.byKey(Key('example-$id')), findsOneWidget);
    await tester.tap(find.byKey(Key('example-$id')));
    await tester.pump();
    expect(
      tester.widget<SelectableText>(find.byKey(const Key('example-body'))).data,
      'hello',
    );
    // No response has been received, so nothing can be saved.
    expect(
      tester
          .widget<TextButton>(find.byKey(const Key('save-example')))
          .onPressed,
      isNull,
    );
    await tester.tap(find.byKey(const Key('delete-example')));
    await tester.pump();
    expect(find.byKey(const Key('no-examples')), findsOneWidget);
    expect(s.repo.examples(r), isEmpty);
  });

  test('snapshot folder port contract: export then merge keeps ids', () {
    final a = WorkspaceSession.memory();
    final b = WorkspaceSession.memory();
    addTearDown(a.close);
    addTearDown(b.close);
    final col = a.repo.createCollection('C');
    a.repo.createRequest(col, const HttpRequestItem(id: '', name: 'R'));
    final port = MemoryFolder();
    port.write(exportSnapshot(a.repo));
    final r = importSnapshot(b.repo, port.files!);
    expect(r.requests, 1);
    expect(b.repo.node(col).name, 'C');
  });
}

class MemoryFolder implements FolderPort {
  Map<String, List<int>>? files;

  @override
  bool get available => true;

  @override
  Future<bool> write(Map<String, List<int>> f) async {
    files = f;
    return true;
  }

  @override
  Future<Map<String, List<int>>?> read() async => files;
}
