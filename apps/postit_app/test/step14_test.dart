import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:postit_app/src/pages/revisions_dialog.dart';
import 'package:postit_app/src/pages/search_dialog.dart';
import 'package:postit_app/src/pages/workspaces_dialog.dart';
import 'package:postit_app/src/state/editor_state.dart';
import 'package:postit_app/src/state/file_port.dart';
import 'package:postit_app/src/state/session.dart';
import 'package:postit_app/src/state/tree_state.dart';
import 'package:postit_app/src/workspace_host.dart';
import 'package:postit_core/postit_core.dart';
import 'package:postit_storage/postit_storage.dart';

import 'step12_test.dart' show FakePort;

({ProviderContainer c, WorkspaceSession s}) setup() {
  final s = WorkspaceSession.memory();
  final c = ProviderContainer(
    overrides: [sessionProvider.overrideWithValue(s)],
  );
  addTearDown(() {
    c.dispose();
    s.close();
  });
  return (c: c, s: s);
}

List<String> names(WorkspaceRepository r, String? parent) =>
    r.children(parent).map((n) => n.name).toList();

class FakeSwitcher implements WorkspaceSwitcher {
  final calls = <String>[];
  @override
  List<RecentWorkspace> recent() => [
    RecentWorkspace(
      id: 'other',
      name: 'Other',
      dbPath: '/tmp/other.postit',
      lastOpenedAt: DateTime(2026),
    ),
  ];
  @override
  Future<void> open(String path) async => calls.add('open $path');
  @override
  Future<void> create(String name) async => calls.add('create $name');
  @override
  Future<void> importBytes(String fileName, Uint8List bytes) async =>
      calls.add('import $fileName ${bytes.length}');
  @override
  Future<Uint8List> exportCurrent() async => Uint8List.fromList([1, 2]);
}

void main() {
  group('drag and drop', () {
    test('requests move into folders and before other requests', () {
      final t = setup();
      final r = t.s.repo;
      final col = r.createCollection('C');
      final f = r.createFolder(col, 'F');
      final a = r.createRequest(col, HttpRequestItem(id: '', name: 'a'));
      final b = r.createRequest(col, HttpRequestItem(id: '', name: 'b'));
      final c = r.createRequest(col, HttpRequestItem(id: '', name: 'c'));
      final actions = t.c.read(treeActionsProvider);

      actions.drop(a, f);
      expect(names(r, f), ['a']);
      expect(names(r, col), ['F', 'b', 'c']);

      // Drag c onto b: c lands before b.
      actions.drop(c, b);
      expect(names(r, col), ['F', 'c', 'b']);
      // Drag c onto b again after moving the earlier one down.
      actions.drop(f, b);
      expect(names(r, col), ['c', 'F', 'b']);
    });

    test('a folder cannot be dropped into itself; collections reorder', () {
      final t = setup();
      final r = t.s.repo;
      final c1 = r.createCollection('One');
      final c2 = r.createCollection('Two');
      final f = r.createFolder(c1, 'F');
      final g = r.createFolder(f, 'G');
      final actions = t.c.read(treeActionsProvider);
      expect(actions.canDrop(f, g), isFalse);
      expect(actions.canDrop(f, f), isFalse);
      actions.drop(f, g);
      expect(names(r, f), ['G']);
      expect(actions.canDrop(c1, f), isFalse);
      expect(actions.canDrop(c2, c1), isTrue);
      actions.drop(c2, c1);
      expect(names(r, null), ['Two', 'One']);
    });
  });

  testWidgets('search finds a request and opens it in a tab', (tester) async {
    final t = setup();
    final col = t.s.repo.createCollection('Billing');
    final id = t.s.repo.createRequest(
      col,
      HttpRequestItem(
        id: '',
        name: 'Create invoice',
        url: 'https://pay.test/i',
      ),
    );
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: t.c,
        child: MaterialApp(
          home: Consumer(
            builder: (context, ref, _) => Scaffold(
              body: TextButton(
                onPressed: () => runSearch(context, ref),
                child: const Text('go'),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('go'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const Key('search-input')), 'pay.test');
    await tester.pump();
    await tester.tap(find.byKey(Key('hit-$id')));
    await tester.pumpAndSettle();
    expect(t.c.read(tabsProvider).active, id);
    expect(t.c.read(expandedProvider), contains(col));
  });

  testWidgets('earlier versions can be restored', (tester) async {
    final t = setup();
    final col = t.s.repo.createCollection('C');
    final id = t.s.repo.createRequest(
      col,
      HttpRequestItem(id: '', name: 'R', url: 'http://one.test'),
    );
    t.s.repo.saveRequest(
      t.s.repo.getRequest(id).copyWith(url: 'http://two.test'),
    );
    t.c.read(editorProvider(id)); // open the editor draft
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: t.c,
        child: MaterialApp(
          home: Consumer(
            builder: (context, ref, _) => Scaffold(
              body: TextButton(
                onPressed: () => showRevisions(context, ref, id),
                child: const Text('go'),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('go'));
    await tester.pumpAndSettle();
    final revs = t.s.repo.revisions(id);
    expect(revs, isNotEmpty);
    await tester.tap(find.byKey(Key('rev-${revs.last.rev}')));
    await tester.pumpAndSettle();
    expect(t.s.repo.getRequest(id).url, 'http://one.test');
    expect(t.c.read(editorProvider(id)).item.url, 'http://one.test');
  });

  test('unique workspace file names', () {
    final dir = Directory.systemTemp.createTempSync('ws');
    addTearDown(() => dir.deleteSync(recursive: true));
    final first = uniqueWorkspacePath(dir, 'My: Work/space');
    expect(first.endsWith('My_ Work_space.postit'), isTrue);
    File(first).writeAsStringSync('x');
    expect(uniqueWorkspacePath(dir, 'My: Work/space'), endsWith(' 2.postit'));
    expect(uniqueWorkspacePath(dir, '  '), endsWith('workspace.postit'));
  });

  testWidgets('workspaces dialog lists others and calls the switcher', (
    tester,
  ) async {
    final t = setup();
    final sw = FakeSwitcher();
    final port = FakePort();
    final c = ProviderContainer(
      overrides: [
        sessionProvider.overrideWithValue(t.s),
        workspaceSwitcherProvider.overrideWithValue(sw),
        filePortProvider.overrideWithValue(port),
      ],
    );
    addTearDown(c.dispose);
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: c,
        child: MaterialApp(
          home: Consumer(
            builder: (context, ref, _) => Scaffold(
              body: TextButton(
                onPressed: () => showWorkspaces(context, ref),
                child: const Text('go'),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('go'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('ws-export')));
    await tester.pumpAndSettle();
    expect(port.saved!.$1, endsWith('.postit'));
    expect(port.saved!.$2, [1, 2]);

    await tester.tap(find.text('go'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('ws-other')));
    await tester.pumpAndSettle();
    expect(sw.calls, ['open /tmp/other.postit']);
  });
}
