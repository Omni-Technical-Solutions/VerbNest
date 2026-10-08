import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:verbnest_app/src/state/session.dart';
import 'package:verbnest_app/src/state/tree_state.dart';
import 'package:verbnest_core/verbnest_core.dart';
import 'package:verbnest_storage/verbnest_storage.dart';

void main() {
  ProviderContainer boot(WorkspaceSession s) {
    final c = ProviderContainer(
      overrides: [sessionProvider.overrideWithValue(s)],
    );
    addTearDown(c.dispose);
    return c;
  }

  test('undoing a delete restores the subtree, variables and position', () {
    final s = WorkspaceSession.memory();
    addTearDown(s.close);
    final actions = boot(s).read(treeActionsProvider);
    final a = actions.newCollection('A');
    final b = actions.newCollection('B');
    final folder = actions.newFolder(a, 'Inner');
    final req = actions.newRequest(folder, name: 'Ping');
    s.repo.saveVariables(VariableOwner.folder(folder), [
      const Variable(key: 'host', value: 'example.com'),
    ]);

    final undo = actions.deleteUndoable(a);
    expect(s.repo.hasNode(a), isFalse);
    expect(s.repo.hasNode(req), isFalse);

    undo();
    expect(s.repo.children(null).map((n) => n.id), [a, b]);
    expect(s.repo.node(req).name, 'Ping');
    expect(s.repo.node(req).parentId, folder);
    expect(s.repo.variables(VariableOwner.folder(folder)).map((v) => v.key), [
      'host',
    ]);
  });

  test('undoing a move or nudge puts the item back', () {
    final s = WorkspaceSession.memory();
    addTearDown(s.close);
    final actions = boot(s).read(treeActionsProvider);
    final a = actions.newCollection('A');
    final b = actions.newCollection('B');
    final r1 = actions.newRequest(a, name: 'one');
    final r2 = actions.newRequest(a, name: 'two');

    actions.nudge(r2, -1)!();
    expect(s.repo.children(a).map((n) => n.id), [r1, r2]);

    final undo = actions.drop(r1, b)!;
    expect(s.repo.node(r1).parentId, b);
    undo();
    expect(s.repo.node(r1).parentId, a);
    expect(s.repo.children(a).map((n) => n.id), [r1, r2]);
    expect(actions.nudge(r1, -1), isNull);
  });
}
