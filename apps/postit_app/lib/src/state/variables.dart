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

/// Variables of [owner] for editing. Secret values are not in the workspace,
/// so they come from the device-local store (interim until the OS secret
/// store lands).
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

void saveVariables(
  WorkspaceSession s,
  VariableOwner owner,
  List<Variable> vars,
) {
  final ws = s.repo.workspaceId;
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
  s.repo.saveVariables(owner, [
    for (final v in vars)
      if (v.key.isNotEmpty)
        Variable(
          key: v.key,
          value: v.secret ? '' : v.value,
          secret: v.secret,
          enabled: v.enabled,
          description: v.description,
        ),
  ]);
}

/// The scope stack for [requestId] (null = no request, e.g. the quick-look
/// panel) and [envId].
VariableScopes buildScopes(
  WorkspaceSession s, {
  String? requestId,
  String? envId,
}) {
  final containers = requestId == null
      ? const <String>[]
      : s.repo.ancestors(requestId).reversed.toList(); // collection first
  return VariableScopes(
    global: loadVariables(s, VariableOwner.global),
    environment: envId == null
        ? const []
        : loadVariables(s, VariableOwner.environment(envId)),
    collection: [
      for (var i = 0; i < containers.length; i++)
        ...s.repo.variables(
          i == 0
              ? VariableOwner.collection(containers[i])
              : VariableOwner.folder(containers[i]),
        ),
    ],
  );
}
