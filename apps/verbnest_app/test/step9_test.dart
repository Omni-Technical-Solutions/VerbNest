import 'package:material_ui/material_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:verbnest_app/src/pages/container_settings_page.dart';
import 'package:verbnest_app/src/pages/environments_page.dart';
import 'package:verbnest_app/src/state/editor_state.dart';
import 'package:verbnest_app/src/state/session.dart';
import 'package:verbnest_app/src/state/settings_state.dart';
import 'package:verbnest_app/src/widgets/request_editor.dart';
import 'package:verbnest_core/verbnest_core.dart';
import 'package:verbnest_storage/verbnest_storage.dart';

import 'editor_test.dart' show FakeEngine;

({ProviderContainer c, WorkspaceSession s, FakeEngine e, String id, String col})
setup() {
  final s = WorkspaceSession.memory();
  final e = FakeEngine();
  final c = ProviderContainer(
    overrides: [
      sessionProvider.overrideWithValue(s),
      engineProvider.overrideWithValue(e),
    ],
  );
  final col = s.repo.createCollection('C');
  final id = s.repo.createRequest(col, HttpRequestItem(id: '', name: 'R'));
  addTearDown(() {
    c.dispose();
    s.close();
  });
  return (c: c, s: s, e: e, id: id, col: col);
}

Future<void> pumpEditor(
  WidgetTester tester,
  ProviderContainer c,
  String id,
) async {
  tester.view.physicalSize = const Size(1000, 1000);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: c,
      child: MaterialApp(
        home: Scaffold(body: RequestEditor(requestId: id)),
      ),
    ),
  );
}

void main() {
  test('undefined variables stop the send until confirmed', () async {
    final t = setup();
    final n = t.c.read(editorProvider(t.id).notifier);
    n.edit((i) => i.copyWith(url: 'http://x.test/{{nope}}'));
    await n.send();
    var st = t.c.read(editorProvider(t.id));
    expect(st.pendingUnresolved, {'nope'});
    expect(t.e.last, isNull);
    expect(st.sending, isFalse);

    await n.send(force: true);
    st = t.c.read(editorProvider(t.id));
    expect(t.e.last, isNotNull);
    expect(st.pendingUnresolved, isEmpty);
    expect(st.response!.status, 201);
  });

  test('turning the warning off sends straight away', () async {
    final t = setup();
    t.c.read(warnUnresolvedProvider.notifier).set(false);
    expect(t.s.repo.settings['warnUnresolved'], false);
    final n = t.c.read(editorProvider(t.id).notifier);
    n.edit((i) => i.copyWith(url: 'http://x.test/{{nope}}'));
    await n.send();
    expect(t.e.last, isNotNull);
    expect(t.c.read(editorProvider(t.id)).unresolved, {'nope'});
  });

  testWidgets('banner offers send anyway and remembers the choice', (
    tester,
  ) async {
    final t = setup();
    final n = t.c.read(editorProvider(t.id).notifier);
    n.edit((i) => i.copyWith(url: 'http://x.test/{{nope}}'));
    await pumpEditor(tester, t.c, t.id);
    await n.send();
    await tester.pump();
    expect(find.byKey(const Key('pending-banner')), findsOneWidget);
    await tester.tap(find.byKey(const Key('dont-warn')));
    await tester.pump();
    await tester.pump();
    expect(t.c.read(warnUnresolvedProvider), isFalse);
    expect(t.e.last, isNotNull);
    expect(find.byKey(const Key('pending-banner')), findsNothing);
    await tester.pump(EditorNotifier.saveDelay);
  });

  testWidgets('custom method can be entered', (tester) async {
    final t = setup();
    await pumpEditor(tester, t.c, t.id);
    await tester.tap(find.byKey(const Key('method')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Custom…').last);
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField).last, 'purge');
    await tester.tap(find.text('Set'));
    await tester.pumpAndSettle();
    expect(t.c.read(editorProvider(t.id)).item.method, 'PURGE');
    await tester.pump(EditorNotifier.saveDelay);
  });

  test('request settings take part in the built request', () async {
    final t = setup();
    final n = t.c.read(editorProvider(t.id).notifier);
    n.edit(
      (i) => i.copyWith(
        url: 'http://x.test',
        settings: const RequestSettings(maxRedirects: 1, autoDecompress: false),
      ),
    );
    await n.send();
    expect(t.e.last!.settings.maxRedirects, 1);
    expect(t.e.last!.settings.autoDecompress, isFalse);
  });

  testWidgets('container settings save description, auth and variables', (
    tester,
  ) async {
    final t = setup();
    tester.view.physicalSize = const Size(1000, 1000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: t.c,
        child: MaterialApp(home: ContainerSettingsPage(containerId: t.col)),
      ),
    );
    await tester.enterText(
      find.byKey(const Key('container-description')),
      'Shop API',
    );
    await tester.pump();
    expect(t.s.repo.description(t.col), 'Shop API');

    await tester.tap(find.text('Auth'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('auth-type')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('bearer').last);
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const Key('auth-token')), 'tok');
    await tester.pump();
    expect((t.s.repo.containerAuth(t.col) as BearerAuth).token, 'tok');
    expect(
      effectiveAuth(const InheritAuth(), t.s.repo.authChain(t.id)),
      isA<BearerAuth>(),
    );

    await tester.tap(find.text('Variables'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('var-add')));
    await tester.pump();
    await tester.enterText(find.byKey(const ValueKey('var-key-0')), 'host');
    await tester.enterText(
      find.byKey(const ValueKey('var-value-0-false')),
      'api.test',
    );
    await tester.pump();
    expect(
      t.s.repo.variables(VariableOwner.collection(t.col)).single.value,
      'api.test',
    );
  });

  testWidgets('duplicate variable names warn instead of failing', (
    tester,
  ) async {
    final t = setup();
    tester.view.physicalSize = const Size(1000, 1000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: t.c,
        child: MaterialApp(
          home: Scaffold(
            body: VariablesEditor(
              initial: const [Variable(key: 'a', value: '1')],
              onChanged: (_, _) {},
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.byKey(const Key('var-add')));
    await tester.pump();
    await tester.enterText(find.byKey(const ValueKey('var-key-1')), 'a');
    await tester.pump();
    expect(find.byKey(const Key('var-duplicates')), findsOneWidget);
  });
}
