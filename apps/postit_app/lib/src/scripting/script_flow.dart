import 'package:postit_core/postit_core.dart';
import 'package:postit_script/postit_script.dart' as core;
import 'package:postit_script/postit_script.dart'
    show
        ScriptEngine,
        ScriptPhase,
        ScriptPhaseResult,
        ScriptScope,
        VariableChange,
        ConsoleLine,
        ScriptVariables;
import 'package:postit_storage/postit_storage.dart';

import '../state/session.dart';
import '../state/variables.dart';

export 'package:postit_script/postit_script.dart'
    show
        ScriptPhaseResult,
        applyRequestMap,
        requestToMap,
        responseToMap,
        scriptsFor;

/// Variables of the open workspace: shared values, device-local current
/// values and the secret store.
class SessionScriptVariables implements ScriptVariables {
  SessionScriptVariables(this.session);

  final WorkspaceSession session;

  @override
  Map<ScriptScope, Map<String, String>> values(
    String requestId,
    String? envId,
    Map<String, String> local,
  ) => _scopeValues(session, requestId, envId, local);

  @override
  void apply(
    String requestId,
    String? envId,
    Map<ScriptScope, List<VariableChange>> changes,
    Map<String, String> local,
    List<ConsoleLine> logs,
  ) => _apply(session, requestId, envId, changes, local, logs);
}

Future<ScriptPhaseResult> runScriptPhase({
  required WorkspaceSession session,
  required ScriptEngine engine,
  required String requestId,
  required HttpRequestItem item,
  required String? envId,
  required ScriptPhase phase,
  required Map<String, Object?> request,
  Map<String, Object?>? response,
  Map<String, String> local = const {},
  Map<String, String> data = const {},
  core.ScriptHost? host,
}) => core.runScriptPhaseWith(
  repo: session.repo,
  variables: SessionScriptVariables(session),
  engine: engine,
  requestId: requestId,
  item: item,
  envId: envId,
  phase: phase,
  request: request,
  response: response,
  local: local,
  data: data,
  host: host,
);

Map<ScriptScope, Map<String, String>> _scopeValues(
  WorkspaceSession s,
  String requestId,
  String? envId,
  Map<String, String> local,
) {
  Map<String, String> of(Iterable<Variable> vars) => {
    for (final v in vars)
      if (v.enabled) v.key: v.value,
  };
  final containers = s.repo.ancestors(requestId).reversed.toList();
  return {
    ScriptScope.local: local,
    ScriptScope.globals: of(loadResolvedVariables(s, VariableOwner.global)),
    ScriptScope.environment: envId == null
        ? const {}
        : of(loadResolvedVariables(s, VariableOwner.environment(envId))),
    ScriptScope.collection: of([
      for (var i = 0; i < containers.length; i++)
        ...loadResolvedVariables(
          s,
          i == 0
              ? VariableOwner.collection(containers[i])
              : VariableOwner.folder(containers[i]),
        ),
    ]),
  };
}

void _apply(
  WorkspaceSession s,
  String requestId,
  String? envId,
  Map<ScriptScope, List<VariableChange>> changes,
  Map<String, String> local,
  List<ConsoleLine> logs,
) {
  for (final entry in changes.entries) {
    if (entry.value.isEmpty) continue;
    if (entry.key == ScriptScope.local) {
      for (final c in entry.value) {
        c.value == null ? local.remove(c.key) : local[c.key] = c.value!;
      }
      continue;
    }
    final owner = switch (entry.key) {
      ScriptScope.globals => VariableOwner.global,
      ScriptScope.environment =>
        envId == null ? null : VariableOwner.environment(envId),
      _ => VariableOwner.collection(s.repo.ancestors(requestId).last),
    };
    if (owner == null) {
      logs.add(
        const ConsoleLine(
          'warn',
          'No environment is selected, so environment variables were not saved',
        ),
      );
      continue;
    }
    _store(s, owner, entry.value);
  }
}

/// Writes script changes as current values, leaving initial values alone.
/// New names are created in [owner]; unset removes the variable.
void _store(
  WorkspaceSession s,
  VariableOwner owner,
  List<VariableChange> changes,
) {
  final vars = [...loadVariables(s, owner)];
  var listChanged = false;
  for (final c in changes) {
    final i = vars.indexWhere((v) => v.key == c.key);
    if (c.value == null) {
      if (i == -1) continue;
      vars.removeAt(i);
      listChanged = true;
      s.setCurrentOverride(owner.kind, owner.id, c.key, '');
    } else if (i == -1) {
      vars.add(Variable(key: c.key, value: c.value!));
      listChanged = true;
    } else if (vars[i].secret) {
      s.secrets.put(s.repo.workspaceId, owner.kind, owner.id, c.key, c.value!);
    } else {
      s.setCurrentOverride(owner.kind, owner.id, c.key, c.value!);
    }
  }
  if (listChanged) saveVariables(s, owner, vars);
}
