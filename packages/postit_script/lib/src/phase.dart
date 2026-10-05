import 'package:postit_core/postit_core.dart';
import 'package:postit_storage/postit_storage.dart';

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
    this.flow = const ScriptFlow(),
  });

  final ScriptFlow flow;

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

/// Where scripts read and write variables. The app stores changes in the
/// workspace and device-local store; the CLI keeps them for the run.
abstract interface class ScriptVariables {
  Map<ScriptScope, Map<String, String>> values(
    String requestId,
    String? envId,
    Map<String, String> local,
  );

  /// Stores the non-local [changes]; local ones go into [local] here.
  void apply(
    String requestId,
    String? envId,
    Map<ScriptScope, List<VariableChange>> changes,
    Map<String, String> local,
    List<ConsoleLine> logs,
  );
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
Future<ScriptPhaseResult> runScriptPhaseWith({
  required WorkspaceRepository repo,
  required ScriptVariables variables,
  required ScriptEngine engine,
  required String requestId,
  required HttpRequestItem item,
  required String? envId,
  required ScriptPhase phase,
  required Map<String, Object?> request,
  Map<String, Object?>? response,
  Map<String, String> local = const {},
  Map<String, String> data = const {},
}) async {
  final codes = scriptsFor(repo, requestId, item.scripts, phase);
  if (codes.isEmpty) return ScriptPhaseResult(local: local);

  final tests = <TestResult>[];
  final logs = <ConsoleLine>[];
  var current = request;
  final localVars = {...local};
  String? error;
  var flow = const ScriptFlow();
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
        variables: variables.values(requestId, envId, localVars),
        environmentName: envName,
        data: data,
      ),
    );
    flow = ScriptFlow(
      next: out.flow.next ?? flow.next,
      stop: flow.stop || out.flow.stop,
      skip: flow.skip || out.flow.skip,
    );
    tests.addAll(out.tests);
    logs.addAll(out.logs);
    variables.apply(requestId, envId, out.changes, localVars, logs);
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
    flow: flow,
  );
}
