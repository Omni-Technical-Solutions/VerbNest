import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:verbnest_core/verbnest_core.dart';
import 'package:verbnest_storage/verbnest_storage.dart';

import 'session.dart';

/// Reverses a tree change.
typedef Undo = void Function();

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
  const TabsState({this.open = const [], this.active, this.preview});

  final List<String> open;
  final String? active;

  /// The tab opened by a single click, shown in italics. The next single click
  /// on another request replaces it; editing it or double-clicking pins it.
  final String? preview;
}

class TabsNotifier extends Notifier<TabsState> {
  @override
  TabsState build() {
    final session = ref.read(sessionProvider);
    final ws = session.repo.workspaceId;
    listenSelf((_, next) {
      session.local.setKv(
        ws,
        'tabs',
        jsonEncode({'open': next.open, 'active': next.active}),
      );
    });
    return _restore(session);
  }

  TabsState _restore(WorkspaceSession session) {
    final raw = session.local.kv(session.repo.workspaceId, 'tabs');
    if (raw == null) return const TabsState();
    try {
      final json = jsonDecode(raw) as Map<String, dynamic>;
      final open = <String>[
        for (final id in (json['open'] as List).cast<String>())
          if (_exists(session.repo, id)) id,
      ];
      final active = json['active'] as String?;
      return TabsState(
        open: open,
        active: open.contains(active) ? active : open.lastOrNull,
      );
    } on Object {
      return const TabsState();
    }
  }

  static bool _exists(WorkspaceRepository repo, String id) {
    try {
      repo.node(id);
      return true;
    } on NotFoundError {
      return false;
    }
  }

  /// Moves to the next (or previous) tab, wrapping around.
  void step(int delta) {
    final open = state.open;
    if (open.length < 2) return;
    final i = open.indexOf(state.active ?? '');
    final next = open[((i == -1 ? 0 : i) + delta) % open.length];
    state = TabsState(open: open, active: next, preview: state.preview);
  }

  /// Opens [id] and makes it active. With [preview] the tab is a preview: it
  /// takes the place of the current preview tab if there is one. Opening an
  /// existing tab without [preview] pins it.
  void open(String id, {bool preview = false}) {
    final open = state.open;
    final current = state.preview;
    if (open.contains(id)) {
      state = TabsState(
        open: open,
        active: id,
        preview: !preview && current == id ? null : current,
      );
      return;
    }
    if (preview && current != null && open.contains(current)) {
      state = TabsState(
        open: [for (final t in open) t == current ? id : t],
        active: id,
        preview: id,
      );
      return;
    }
    state = TabsState(
      open: [...open, id],
      active: id,
      preview: preview ? id : current,
    );
  }

  /// Turns a preview tab into a normal one.
  void pin(String id) {
    if (state.preview != id) return;
    state = TabsState(open: state.open, active: state.active);
  }

  /// Moves a tab to [newIndex], its index once it has been taken out of its
  /// old place (what `ReorderableListView.onReorderItem` reports).
  void move(int oldIndex, int newIndex) {
    final open = [...state.open];
    if (oldIndex < 0 || oldIndex >= open.length) return;
    open.insert(newIndex.clamp(0, open.length - 1), open.removeAt(oldIndex));
    state = TabsState(open: open, active: state.active, preview: state.preview);
  }

  void activate(String id) {
    if (state.open.contains(id)) {
      state = TabsState(open: state.open, active: id, preview: state.preview);
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
    state = TabsState(
      open: remaining,
      active: active,
      preview: state.preview == id ? null : state.preview,
    );
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

class _Captured {
  const _Captured({
    required this.raw,
    required this.owner,
    required this.variables,
    required this.examples,
    required this.children,
  });

  final Map<String, Object?> raw;
  final VariableOwner? owner;
  final List<Variable> variables;
  final List<ExampleInfo> examples;
  final List<_Captured> children;
}

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

  /// Deletes [id] and returns a function that puts the subtree back in its
  /// old place, with container variables and saved examples. Version history
  /// is not restored.
  Undo deleteUndoable(String id) {
    final node = _repo.node(id);
    final parent = node.parentId;
    final index = _repo.children(parent).indexWhere((n) => n.id == id);
    final captured = _capture(id);
    delete(id);
    return () {
      _put(captured, parent);
      _repo.move(id, parent, index);
    };
  }

  _Captured _capture(String id) {
    final node = _repo.node(id);
    final owner = switch (node.kind) {
      NodeKind.collection => VariableOwner.collection(id),
      NodeKind.folder => VariableOwner.folder(id),
      NodeKind.request => null,
    };
    return _Captured(
      raw: _repo.rawNode(id),
      owner: owner,
      variables: owner == null ? const [] : _repo.variables(owner),
      examples: node.isContainer ? const [] : _repo.examples(id),
      children: [for (final c in _repo.children(id)) _capture(c.id)],
    );
  }

  void _put(_Captured c, String? parent) {
    _repo.restoreNode(c.raw, parent);
    if (c.owner != null && c.variables.isNotEmpty) {
      _repo.saveVariables(c.owner!, c.variables);
    }
    for (final e in c.examples) {
      _repo.restoreExample(e);
    }
    for (final child in c.children) {
      _put(child, c.raw['id'] as String);
    }
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
  ///
  /// Returns a function that moves it back, or null when nothing moved.
  Undo? drop(String id, String targetId) {
    if (!canDrop(id, targetId)) return null;
    final undo = _undoMove(id);
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
    return undo;
  }

  Undo _undoMove(String id) {
    final parent = _repo.node(id).parentId;
    final index = _repo.children(parent).indexWhere((n) => n.id == id);
    return () => _repo.move(id, parent, index);
  }

  /// Moves [id] one place up (-1) or down (+1) among its siblings.
  Undo? nudge(String id, int delta) {
    final node = _repo.node(id);
    final siblings = _repo.children(node.parentId).map((n) => n.id).toList();
    final target = siblings.indexOf(id) + delta;
    if (target < 0 || target >= siblings.length) return null;
    final undo = _undoMove(id);
    _repo.move(id, node.parentId, target);
    return undo;
  }
}

final treeActionsProvider = Provider<TreeActions>(TreeActions.new);
