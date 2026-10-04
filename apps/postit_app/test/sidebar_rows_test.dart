import 'package:flutter_test/flutter_test.dart';
import 'package:postit_app/src/state/session.dart';
import 'package:postit_app/src/state/sidebar_rows.dart';
import 'package:postit_app/src/state/tree_state.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

void main() {
  test('flatten honours expansion and filter', () {
    final s = WorkspaceSession.memory();
    addTearDown(s.close);
    final c = s.repo.createCollection('Alpha');
    final f = s.repo.createFolder(c, 'Inner');
    s.repo.createFolder(f, 'Deep');
    s.repo.createCollection('Beta');

    expect(sidebarRows(s.repo.children, {}, '').map((r) => r.node.name), [
      'Alpha',
      'Beta',
    ]);
    expect(sidebarRows(s.repo.children, {c}, '').map((r) => r.node.name), [
      'Alpha',
      'Inner',
      'Beta',
    ]);
    final filtered = sidebarRows(s.repo.children, {}, 'deep');
    expect(filtered.map((r) => r.node.name), contains('Deep'));
    expect(filtered.map((r) => r.node.name), isNot(contains('Beta')));
  });

  test('tabs open, activate and close', () {
    final s = WorkspaceSession.memory();
    addTearDown(s.close);
    final container = ProviderContainer(
      overrides: [sessionProvider.overrideWithValue(s)],
    );
    addTearDown(container.dispose);
    final tabs = container.read(tabsProvider.notifier);
    tabs.open('a');
    tabs.open('b');
    tabs.open('a');
    expect(container.read(tabsProvider).open, ['a', 'b']);
    expect(container.read(tabsProvider).active, 'a');
    tabs.close('a');
    expect(container.read(tabsProvider).active, 'b');
    tabs.close('b');
    expect(container.read(tabsProvider).active, isNull);
  });

  test('delete prunes tabs; nudge reorders', () {
    final s = WorkspaceSession.memory();
    addTearDown(s.close);
    final container = ProviderContainer(
      overrides: [sessionProvider.overrideWithValue(s)],
    );
    addTearDown(container.dispose);
    final actions = container.read(treeActionsProvider);
    final a = actions.newCollection('A');
    final b = actions.newCollection('B');
    final r = actions.newRequest(a);
    expect(container.read(tabsProvider).active, r);
    actions.nudge(b, -1);
    expect(s.repo.children(null).map((n) => n.id), [b, a]);
    actions.delete(a);
    expect(container.read(tabsProvider).open, isEmpty);
  });
}
