import 'package:verbnest_core/verbnest_core.dart';
import 'package:verbnest_storage/verbnest_storage.dart';

import 'script_engine.dart';
import 'script_host.dart';
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
  ScriptHost? host,
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
    final out = await _runWithSends(
      engine,
      host,
      () => ScriptInput(
        code: code,
        phase: phase,
        requestName: item.name,
        requestId: requestId,
        request: current,
        response: response,
        variables: variables.values(requestId, envId, localVars),
        environmentName: envName,
        data: data,
        cookies: host?.cookiesFor('${current['url']}') ?? const {},
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

/// Most `pm.sendRequest` calls one script may make.
const maxScriptRequests = 10;

/// Longest a script and its requests may take together.
const scriptRequestBudget = Duration(seconds: 60);

/// Runs a script and answers its `pm.sendRequest` calls. The script is run
/// again after each answer (see the prelude); [make] builds a fresh input
/// each time so variable values start from the same state.
Future<ScriptOutput> _runWithSends(
  ScriptEngine engine,
  ScriptHost? host,
  ScriptInput Function() make,
) async {
  final results = <Map<String, Object?>>[];
  final watch = Stopwatch()..start();
  while (true) {
    final base = make();
    final out = await engine.run(
      ScriptInput(
        code: base.code,
        phase: base.phase,
        requestName: base.requestName,
        requestId: base.requestId,
        request: base.request,
        response: base.response,
        variables: base.variables,
        environmentName: base.environmentName,
        data: base.data,
        cookies: base.cookies,
        sendResults: List.of(results),
      ),
    );
    final need = out.needs;
    if (need == null) return out;
    if (results.length >= maxScriptRequests) {
      return out.withError(
        'A script may make at most $maxScriptRequests pm.sendRequest calls',
      );
    }
    if (watch.elapsed > scriptRequestBudget) {
      return ScriptOutput.failed(
        'Script requests took longer than ${scriptRequestBudget.inSeconds} s',
        elapsed: watch.elapsed,
      );
    }
    if (host == null) {
      results.add({'error': 'pm.sendRequest is not available here'});
      continue;
    }
    try {
      results.add({'response': await host.send(need)});
    } on Object catch (e) {
      results.add({'error': e is FormatException ? e.message : '$e'});
    }
  }
}
