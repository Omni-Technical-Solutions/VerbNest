import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:postit_core/postit_core.dart';
import 'package:postit_storage/postit_storage.dart';

import 'session.dart';

/// Bumps whenever the workspace changes, so views re-read the repository.
final workspaceVersionProvider = StreamProvider<int>((ref) async* {
  final repo = ref.watch(repositoryProvider);
  var version = 0;
  yield version;
  await for (final _ in repo.changes) {
    yield ++version;
  }
});

/// Children of [parentId] (null = collections), refreshed on every change.
final childrenProvider = Provider.family<List<NodeInfo>, String?>((
  ref,
  parentId,
) {
  ref.watch(workspaceVersionProvider);
  return ref.watch(repositoryProvider).children(parentId);
});

/// Which containers are expanded in the sidebar.
class ExpandedNotifier extends Notifier<Set<String>> {
  @override
  Set<String> build() => {};

  void expand(String id) => state = {...state, id};

  void toggle(String id) =>
      state = state.contains(id) ? ({...state}..remove(id)) : {...state, id};
}

final expandedProvider = NotifierProvider<ExpandedNotifier, Set<String>>(
  ExpandedNotifier.new,
);

/// Open request tabs and the active one.
class TabsState {
  const TabsState({this.open = const [], this.active});

  final List<String> open;
  final String? active;
}

class TabsNotifier extends Notifier<TabsState> {
  @override
  TabsState build() => const TabsState();

  void open(String id) => state = TabsState(
    open: state.open.contains(id) ? state.open : [...state.open, id],
    active: id,
  );

  void activate(String id) {
    if (state.open.contains(id)) {
      state = TabsState(open: state.open, active: id);
    }
  }

  void close(String id) {
    final index = state.open.indexOf(id);
    if (index == -1) return;
    final remaining = [...state.open]..removeAt(index);
    final active = state.active != id
        ? state.active
        : (remaining.isEmpty
              ? null
              : remaining[index.clamp(0, remaining.length - 1)]);
    state = TabsState(open: remaining, active: active);
  }

  /// Drops tabs whose request no longer exists.
  void prune(bool Function(String id) exists) {
    for (final id in [...state.open]) {
      if (!exists(id)) close(id);
    }
  }
}

final tabsProvider = NotifierProvider<TabsNotifier, TabsState>(
  TabsNotifier.new,
);

/// Commands the sidebar issues; each wraps one repository operation.
class TreeActions {
  TreeActions(this._ref);

  final Ref _ref;

  WorkspaceRepository get _repo => _ref.read(repositoryProvider);

  String newCollection(String name) {
    final id = _repo.createCollection(name);
    _ref.read(expandedProvider.notifier).expand(id);
    return id;
  }

  String newFolder(String parentId, String name) {
    final id = _repo.createFolder(parentId, name);
    _ref.read(expandedProvider.notifier).expand(parentId);
    return id;
  }

  String newRequest(String parentId, {String name = 'New request'}) {
    final id = _repo.createRequest(
      parentId,
      HttpRequestItem(id: '', name: name),
    );
    _ref.read(expandedProvider.notifier).expand(parentId);
    _ref.read(tabsProvider.notifier).open(id);
    return id;
  }

  void rename(String id, String name) => _repo.rename(id, name);

  String duplicate(String id) => _repo.duplicate(id);

  void delete(String id) {
    _repo.delete(id);
    _ref.read(tabsProvider.notifier).prune((tab) {
      try {
        _repo.node(tab);
        return true;
      } on NotFoundError {
        return false;
      }
    });
  }

  /// Whether dropping [id] on [targetId] is allowed.
  bool canDrop(String id, String targetId) {
    if (id == targetId) return false;
    final dragged = _repo.node(id);
    final target = _repo.node(targetId);
    if (dragged.kind == NodeKind.collection) {
      return target.kind == NodeKind.collection;
    }
    // A container cannot go inside its own subtree.
    return !_repo.ancestors(targetId).contains(id);
  }

  /// Drops [id] on [targetId]: into a folder or collection (at the end), or
  /// before a request. A collection dropped on a collection takes its place.
  void drop(String id, String targetId) {
    if (!canDrop(id, targetId)) return;
    final dragged = _repo.node(id);
    final target = _repo.node(targetId);
    if (dragged.kind == NodeKind.collection) {
      final order = _repo
          .children(null)
          .map((n) => n.id)
          .where((x) => x != id)
          .toList();
      _repo.move(id, null, order.indexOf(targetId));
    } else if (target.isContainer) {
      _repo.move(id, targetId, _repo.children(targetId).length);
      _ref.read(expandedProvider.notifier).expand(targetId);
    } else {
      // Without the dragged item, so the index is "before the target".
      final order = _repo
          .children(target.parentId)
          .map((n) => n.id)
          .where((x) => x != id)
          .toList();
      _repo.move(id, target.parentId, order.indexOf(targetId));
    }
  }

  /// Moves [id] one place up (-1) or down (+1) among its siblings.
  void nudge(String id, int delta) {
    final node = _repo.node(id);
    final siblings = _repo.children(node.parentId).map((n) => n.id).toList();
    final target = siblings.indexOf(id) + delta;
    if (target < 0 || target >= siblings.length) return;
    _repo.move(id, node.parentId, target);
  }
}

final treeActionsProvider = Provider<TreeActions>(TreeActions.new);
