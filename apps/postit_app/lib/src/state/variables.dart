import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:postit_core/postit_core.dart';
import 'package:postit_storage/postit_storage.dart';

import 'session.dart';
import 'tree_state.dart';

/// The environment requests resolve against, remembered in the workspace.
class ActiveEnvNotifier extends Notifier<String?> {
  @override
  String? build() {
    final repo = ref.read(repositoryProvider);
    final id = repo.defaultEnvironmentId;
    if (id == null) return null;
    return repo.environments().any((e) => e.id == id) ? id : null;
  }

  void select(String? id) {
    ref.read(repositoryProvider).defaultEnvironmentId = id;
    state = id;
  }
}

final activeEnvProvider = NotifierProvider<ActiveEnvNotifier, String?>(
  ActiveEnvNotifier.new,
);

final environmentsProvider = Provider<List<Environment>>((ref) {
  ref.watch(workspaceVersionProvider);
  return ref.watch(repositoryProvider).environments();
});

/// Bumped after each send so the history page reloads.
class HistoryTick extends Notifier<int> {
  @override
  int build() => 0;

  void bump() => state++;
}

final historyTickProvider = NotifierProvider<HistoryTick, int>(HistoryTick.new);

/// Variables of [owner] for editing: the initial (shared) value for plain
/// variables, the secret value for secrets. Secrets come from the secret
/// store, never from the workspace file.
List<Variable> loadVariables(WorkspaceSession s, VariableOwner owner) {
  final current = s.secrets.values(s.repo.workspaceId, owner.kind, owner.id);
  return [
    for (final v in s.repo.variables(owner))
      v.secret
          ? Variable(
              key: v.key,
              value: current[v.key] ?? '',
              secret: true,
              enabled: v.enabled,
              description: v.description,
            )
          : v,
  ];
}

/// Device-local current values of plain variables (FR-VAR-002), by name.
Map<String, String> loadCurrentValues(
  WorkspaceSession s,
  VariableOwner owner,
) => s.currentOverrides(owner.kind, owner.id);

/// Variables as they resolve: a non-empty current value replaces the initial
/// value of a plain variable.
List<Variable> loadResolvedVariables(WorkspaceSession s, VariableOwner owner) {
  final current = loadCurrentValues(s, owner);
  return [
    for (final v in loadVariables(s, owner))
      if (!v.secret && (current[v.key] ?? '').isNotEmpty)
        Variable(
          key: v.key,
          value: current[v.key]!,
          enabled: v.enabled,
          description: v.description,
        )
      else
        v,
  ];
}

void saveVariables(
  WorkspaceSession s,
  VariableOwner owner,
  List<Variable> vars, {
  Map<String, String>? current,
}) {
  final ws = s.repo.workspaceId;
  if (current != null) {
    final names = {
      for (final v in vars)
        if (!v.secret && v.key.isNotEmpty) v.key,
    };
    for (final key in loadCurrentValues(s, owner).keys) {
      if (!names.contains(key)) {
        s.setCurrentOverride(owner.kind, owner.id, key, '');
      }
    }
    for (final key in names) {
      s.setCurrentOverride(owner.kind, owner.id, key, current[key] ?? '');
    }
  }
  final old = s.secrets.values(ws, owner.kind, owner.id);
  final keepSecrets = <String>{};
  for (final v in vars) {
    if (v.secret && v.key.isNotEmpty) {
      s.secrets.put(ws, owner.kind, owner.id, v.key, v.value);
      keepSecrets.add(v.key);
    }
  }
  for (final key in old.keys) {
    if (!keepSecrets.contains(key)) {
      s.secrets.remove(ws, owner.kind, owner.id, key);
    }
  }
  // The workspace rejects repeated names; the last row wins and the editor
  // shows a warning for the duplicates.
  final byKey = <String, Variable>{};
  for (final v in vars) {
    if (v.key.isEmpty) continue;
    byKey[v.key] = Variable(
      key: v.key,
      value: v.secret ? '' : v.value,
      secret: v.secret,
      enabled: v.enabled,
      description: v.description,
    );
  }
  s.repo.saveVariables(owner, byKey.values.toList());
}

/// The scope stack for [requestId] (null = no request, e.g. the quick-look
/// panel) and [envId].
VariableScopes buildScopes(
  WorkspaceSession s, {
  String? requestId,
  String? envId,
  Map<String, String> local = const {},
  Map<String, String> data = const {},
}) {
  final containers = requestId == null
      ? const <String>[]
      : s.repo.ancestors(requestId).reversed.toList(); // collection first
  return VariableScopes(
    local: [
      for (final e in local.entries) Variable(key: e.key, value: e.value),
    ],
    data: [for (final e in data.entries) Variable(key: e.key, value: e.value)],
    global: loadResolvedVariables(s, VariableOwner.global),
    environment: envId == null
        ? const []
        : loadResolvedVariables(s, VariableOwner.environment(envId)),
    collection: [
      for (var i = 0; i < containers.length; i++)
        ...loadResolvedVariables(
          s,
          i == 0
              ? VariableOwner.collection(containers[i])
              : VariableOwner.folder(containers[i]),
        ),
    ],
  );
}
