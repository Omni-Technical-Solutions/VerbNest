import 'package:postit_core/postit_core.dart';
import 'package:postit_http/postit_http.dart';
import 'package:postit_storage/postit_storage.dart';

import '../state/session.dart';
import '../state/variables.dart';
import 'script_engine.dart';
import 'script_io.dart';

/// What all scripts of one phase did, in run order.
class ScriptPhaseResult {
  const ScriptPhaseResult({
    this.tests = const [],
    this.logs = const [],
    this.error,
    this.request,
    this.local = const {},
  });

  final List<TestResult> tests;
  final List<ConsoleLine> logs;

  /// The first failure; later scripts do not run after it.
  final String? error;

  /// The request after pre-request scripts, if any ran.
  final Map<String, Object?>? request;

  /// `pm.variables.set` values, visible to later scripts and the request.
  final Map<String, String> local;

  bool get ranNothing =>
      tests.isEmpty && logs.isEmpty && error == null && request == null;
}

/// The scripts to run for [requestId] in order: collection, folders, request
/// (FR-SCR-001). Empty ones are dropped.
List<String> scriptsFor(
  WorkspaceRepository repo,
  String requestId,
  Scripts own,
  ScriptPhase phase,
) {
  String pick(Scripts s) => phase == ScriptPhase.pre ? s.pre : s.post;
  return [
    for (final s in [...repo.scriptsChain(requestId), own])
      if (pick(s).trim().isNotEmpty) pick(s),
  ];
}

/// Runs the scripts of [phase] one after the other. Variable changes are
/// stored after each script, so the next one and the request itself see them.
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
}) async {
  final repo = session.repo;
  final codes = scriptsFor(repo, requestId, item.scripts, phase);
  if (codes.isEmpty) return ScriptPhaseResult(local: local);

  final tests = <TestResult>[];
  final logs = <ConsoleLine>[];
  var current = request;
  var localVars = {...local};
  String? error;
  var ranRequest = false;
  final envName = envId == null
      ? null
      : repo.environments().where((e) => e.id == envId).firstOrNull?.name;

  for (final code in codes) {
    final out = await engine.run(
      ScriptInput(
        code: code,
        phase: phase,
        requestName: item.name,
        requestId: requestId,
        request: current,
        response: response,
        variables: _scopeValues(session, requestId, envId, localVars),
        environmentName: envName,
      ),
    );
    tests.addAll(out.tests);
    logs.addAll(out.logs);
    _apply(session, requestId, envId, out.changes, localVars, logs);
    if (out.request != null) {
      current = out.request!;
      ranRequest = true;
    }
    if (out.error != null) {
      error = out.error;
      break;
    }
  }
  return ScriptPhaseResult(
    tests: tests,
    logs: logs,
    error: error,
    request: ranRequest ? current : null,
    local: localVars,
  );
}

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

/// The request as a script sees it before variables are replaced: the
/// enabled headers and the raw body text.
Map<String, Object?> requestToMap(HttpRequestItem item) => {
  'method': item.method,
  'url': item.url,
  'headers': [
    for (final h in item.headers)
      if (h.enabled && h.key.isNotEmpty) {'key': h.key, 'value': h.value},
  ],
  'body': switch (item.body) {
    RawBody(:final text) => text,
    _ => '',
  },
};

/// Puts what a pre-request script changed back into [item]. Disabled
/// headers stay; a body change only applies to raw bodies, or turns an empty
/// body into a text body.
HttpRequestItem applyRequestMap(
  HttpRequestItem item,
  Map<String, Object?> map,
) {
  final url = map['url'] as String? ?? item.url;
  final method = (map['method'] as String? ?? item.method).trim();
  final scripted = [
    for (final h in (map['headers'] as List? ?? const []))
      KeyValue(
        key: (h as Map)['key'] as String,
        value: h['value'] as String? ?? '',
      ),
  ];
  var result = item.copyWith(
    method: method.isEmpty ? item.method : method.toUpperCase(),
    headers: [...scripted, ...item.headers.where((h) => !h.enabled)],
  );
  if (url != item.url) {
    final oldVars = {for (final v in item.pathVars) v.key: v};
    result = result.copyWith(
      url: url,
      params: [...UrlText.params(url), ...item.params.where((p) => !p.enabled)],
      pathVars: [
        for (final n in UrlText.pathVariables(url))
          oldVars[n] ?? KeyValue(key: n),
      ],
    );
  }
  final body = map['body'] as String? ?? '';
  final current = item.body;
  if (current is RawBody && current.text != body) {
    result = result.copyWith(body: RawBody(current.language, body));
  } else if (current is! RawBody && body.isNotEmpty) {
    result = result.copyWith(body: RawBody(RawBodyLanguage.text, body));
  }
  return result;
}

/// The response as scripts see it.
Map<String, Object?> responseToMap(HttpResponseRecord r) => {
  'code': r.status,
  'status': r.reason,
  'headers': [
    for (final (k, v) in r.headers) {'key': k, 'value': v},
  ],
  'body': r.bodyText,
  'time': r.timings.total.inMilliseconds,
  'size': r.body.length,
};
