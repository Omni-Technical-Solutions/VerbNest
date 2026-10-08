import 'dart:io' show IOException;

import 'package:verbnest_core/verbnest_core.dart';
import 'package:verbnest_http/verbnest_http.dart';
import 'package:verbnest_script/verbnest_script.dart';
import 'package:verbnest_storage/verbnest_storage.dart';

import 'history_recorder.dart';
import 'request_pipeline.dart';
import 'runner.dart';

/// The variable scopes of [requestId] as the app builds them, minus the
/// device-local current values. Secret variables are empty unless [secrets]
/// or [overrides] supply them.
VariableScopes workspaceScopes(
  WorkspaceRepository repo,
  String requestId, {
  String? envId,
  Map<String, String> overrides = const {},
  Map<String, String> data = const {},
  SecretStore? secrets,
  Map<ScriptScope, Map<String, String>> scriptValues = const {},
}) {
  List<Variable> vars(VariableOwner owner) {
    final stored =
        secrets?.values(repo.workspaceId, owner.kind, owner.id) ?? const {};
    return [
      for (final v in repo.variables(owner))
        v.secret
            ? Variable(
                key: v.key,
                value: stored[v.key] ?? '',
                secret: true,
                enabled: v.enabled,
                description: v.description,
              )
            : v,
    ];
  }

  List<Variable> extra(ScriptScope scope) => [
    for (final e in (scriptValues[scope] ?? const <String, String>{}).entries)
      Variable(key: e.key, value: e.value),
  ];

  final containers = repo.ancestors(requestId).reversed.toList();
  return VariableScopes(
    local: [
      for (final e in overrides.entries) Variable(key: e.key, value: e.value),
    ],
    data: [for (final e in data.entries) Variable(key: e.key, value: e.value)],
    global: [...vars(VariableOwner.global), ...extra(ScriptScope.globals)],
    environment: envId == null
        ? const []
        : [
            ...vars(VariableOwner.environment(envId)),
            ...extra(ScriptScope.environment),
          ],
    collection: [
      for (var i = 0; i < containers.length; i++)
        ...vars(
          i == 0
              ? VariableOwner.collection(containers[i])
              : VariableOwner.folder(containers[i]),
        ),
      ...extra(ScriptScope.collection),
      ...extra(ScriptScope.collection),
    ],
  );
}

/// Sends requests of a run without a UI and without scripts (no JavaScript
/// runtime outside the app). Variables come from the workspace file plus
/// [overrides]; secret variables are empty unless [overrides] or [secrets]
/// supply them.
class HeadlessSender {
  HeadlessSender({
    required this.repo,
    required this.engine,
    this.defaults = const HttpSettings(),
    this.envId,
    this.overrides = const {},
    this.secrets,
    this.secretHostFlags = const {},
    OAuth2TokenCache? oauthCache,
    this.scripts,
    this.history,
  }) : _oauthCache = oauthCache ?? OAuth2TokenCache();

  final WorkspaceRepository repo;
  final HttpEngine engine;
  final HttpSettings defaults;
  final String? envId;

  /// Highest-precedence variables, like `--var name=value`.
  final Map<String, String> overrides;
  final SecretStore? secrets;

  /// Extra secret-to-host approvals (`name` or `*` to hosts), not stored.
  final Map<String, Set<String>> secretHostFlags;

  /// Records every request that is sent, when set.
  final HistoryRecorder? history;
  final OAuth2TokenCache _oauthCache;

  /// Runs pre-request and post-response scripts when set; without it,
  /// requests that have scripts are listed in [scriptsSkipped].
  final ScriptEngine? scripts;

  /// Variable values scripts set during the run (kept in memory only).
  late final _scriptVars = MemoryScriptVariables(repo);

  late final _scriptHost = EngineScriptHost(engine, settings: defaults);

  /// Requests whose pre-request or post-response scripts were not run.
  final Set<String> scriptsSkipped = {};

  VariableScopes scopesFor(String requestId, Map<String, String> data) =>
      workspaceScopes(
        repo,
        requestId,
        envId: envId,
        overrides: overrides,
        data: data,
        secrets: secrets,
        scriptValues: _scriptVars.state,
      );

  /// A [RunStep] for [executeRun].
  Future<RunStepResult> step(
    String id,
    String name,
    int iteration,
    Map<String, String> row,
  ) async {
    var item = repo.getRequest(id);
    final hasScripts =
        !item.scripts.isEmpty || repo.scriptsChain(id).any((s) => !s.isEmpty);
    if (hasScripts && scripts == null) scriptsSkipped.add(name);
    final logs = <ConsoleLine>[];
    PreparedRequest? sentPrepared;
    RunEntry entry({
      HttpResponseRecord? response,
      List<TestResult> tests = const [],
      String? error,
    }) => RunEntry(
      iteration: iteration,
      requestId: id,
      name: name,
      method: item.method,
      url: response == null
          ? item.url
          : sentPrepared?.masker.maskText(response.sent.url.toString()) ??
                response.sent.url.toString(),
      status: response?.status,
      reason: response?.reason ?? '',
      timeMs: response?.timings.total.inMilliseconds ?? 0,
      tests: tests,
      error: error,
    );
    try {
      var local = <String, String>{};
      var flow = const ScriptFlow();
      final engineForScripts = scripts;
      if (engineForScripts != null && hasScripts) {
        final pre = await runScriptPhaseWith(
          repo: repo,
          variables: _scriptVars,
          engine: engineForScripts,
          requestId: id,
          item: item,
          envId: envId,
          phase: ScriptPhase.pre,
          request: requestToMap(item),
          data: row,
          host: _scriptHost,
        );
        local = pre.local;
        logs.addAll(pre.logs);
        if (pre.error != null) {
          return RunStepResult(
            entry(error: 'Pre-request script failed: ${pre.error}'),
            RunFlow(next: pre.flow.next, stop: pre.flow.stop),
          );
        }
        if (pre.request != null) item = applyRequestMap(item, pre.request!);
        flow = pre.flow;
        if (flow.skip) {
          return RunStepResult(
            RunEntry(
              iteration: iteration,
              requestId: id,
              name: name,
              method: item.method,
              url: item.url,
              timeMs: 0,
              skipped: true,
            ),
            RunFlow(next: flow.next, stop: flow.stop, skip: true),
          );
        }
      }
      final resolver = VariableResolver(
        workspaceScopes(
          repo,
          id,
          envId: envId,
          overrides: {...overrides, ...local},
          data: row,
          secrets: secrets,
          scriptValues: _scriptVars.state,
        ),
      );
      if (isLiveUrl(resolver.resolve(item.url).value)) {
        return RunStepResult(
          RunEntry(
            iteration: iteration,
            requestId: id,
            name: name,
            method: item.method,
            url: item.url,
            reason: liveSkipNote,
            timeMs: 0,
            skipped: true,
          ),
          const RunFlow(skip: true),
        );
      }
      final prepared = await prepareRequest(
        repo: repo,
        requestId: id,
        item: item,
        resolver: resolver,
        defaults: defaults,
        oauthToken: (auth) => _oauthToken(auth, resolver),
        secretHosts: secrets == null
            ? null
            : SecretHosts(secrets!, repo.workspaceId, extra: secretHostFlags),
      );
      sentPrepared = prepared;
      final response = await sendPrepared(engine, prepared);
      history?.record(
        requestId: id,
        item: item,
        prepared: prepared,
        response: response,
      );
      final tests = evaluateAssertions(item, response, resolver);
      String? scriptError;
      if (engineForScripts != null && hasScripts) {
        final post = await runScriptPhaseWith(
          repo: repo,
          variables: _scriptVars,
          engine: engineForScripts,
          requestId: id,
          item: item,
          envId: envId,
          phase: ScriptPhase.post,
          request: requestToMap(item),
          response: responseToMap(response),
          local: local,
          data: row,
          host: _scriptHost,
        );
        tests.addAll(post.tests);
        logs.addAll(post.logs);
        scriptError = post.error == null
            ? null
            : 'Post-response script failed: ${post.error}';
        flow = ScriptFlow(
          next: post.flow.next ?? flow.next,
          stop: post.flow.stop || flow.stop,
        );
      }
      lastLogs[id] = logs;
      return RunStepResult(
        entry(response: response, tests: tests, error: scriptError),
        RunFlow(next: flow.next, stop: flow.stop),
      );
    } on OAuth2Error catch (e) {
      return RunStepResult(entry(error: e.message));
    } on RequestBuildError catch (e) {
      return RunStepResult(entry(error: e.message));
    } on HttpEngineError catch (e) {
      history?.record(
        requestId: id,
        item: item,
        prepared: sentPrepared,
        error: e.message,
      );
      return RunStepResult(entry(error: e.message));
    } on IOException catch (e) {
      history?.record(
        requestId: id,
        item: item,
        prepared: sentPrepared,
        error: '$e',
      );
      return RunStepResult(entry(error: '$e'));
    }
  }

  /// Console output of each request's scripts from its latest run.
  final Map<String, List<ConsoleLine>> lastLogs = {};

  Future<Auth> _oauthToken(OAuth2Auth auth, VariableResolver resolver) async {
    final resolved = auth.mapText((t) => resolver.resolve(t).value);
    if (resolved.interactive) {
      throw OAuth2Error(
        'Browser sign-in is not available in the CLI; use a token '
        'variable or a non-interactive OAuth 2.0 grant',
      );
    }
    final cache = _oauthCache;
    var token = cache.get(resolved);
    if (token == null) {
      token = await fetchOAuth2Token(engine, resolved, settings: defaults);
      cache.put(resolved, token);
    }
    return BearerAuth(token: token.accessToken);
  }
}

/// WebSocket URLs cannot be run as a request/response step.
bool isLiveUrl(String url) =>
    RegExp(r'^\s*wss?://', caseSensitive: false).hasMatch(url);

const liveSkipNote = 'Skipped: WebSocket requests are not run by the runner';

/// Script variable changes kept for the length of a run, never written to
/// the workspace file.
class MemoryScriptVariables implements ScriptVariables {
  MemoryScriptVariables(this.repo);

  final WorkspaceRepository repo;

  /// Values scripts set, by scope; unset names are removed.
  final Map<ScriptScope, Map<String, String>> state = {};

  /// Names scripts removed, hidden from the workspace values below.
  final Map<ScriptScope, Set<String>> _unset = {};

  Map<String, String> _of(Iterable<Variable> vars) => {
    for (final v in vars)
      if (v.enabled) v.key: v.value,
  };

  @override
  Map<ScriptScope, Map<String, String>> values(
    String requestId,
    String? envId,
    Map<String, String> local,
  ) {
    final containers = repo.ancestors(requestId).reversed.toList();
    final base = {
      ScriptScope.globals: _of(repo.variables(VariableOwner.global)),
      ScriptScope.environment: envId == null
          ? <String, String>{}
          : _of(repo.variables(VariableOwner.environment(envId))),
      ScriptScope.collection: _of([
        for (var i = 0; i < containers.length; i++)
          ...repo.variables(
            i == 0
                ? VariableOwner.collection(containers[i])
                : VariableOwner.folder(containers[i]),
          ),
      ]),
    };
    return {
      ScriptScope.local: local,
      for (final e in base.entries)
        e.key: {
          for (final kv in {...e.value, ...?state[e.key]}.entries)
            if (!(_unset[e.key]?.contains(kv.key) ?? false)) kv.key: kv.value,
        },
    };
  }

  @override
  void apply(
    String requestId,
    String? envId,
    Map<ScriptScope, List<VariableChange>> changes,
    Map<String, String> local,
    List<ConsoleLine> logs,
  ) {
    for (final e in changes.entries) {
      if (e.key == ScriptScope.local) {
        for (final c in e.value) {
          c.value == null ? local.remove(c.key) : local[c.key] = c.value!;
        }
        continue;
      }
      final target = state[e.key] ??= {};
      final unset = _unset[e.key] ??= {};
      for (final c in e.value) {
        if (c.value == null) {
          target.remove(c.key);
          unset.add(c.key);
        } else {
          target[c.key] = c.value!;
          unset.remove(c.key);
        }
      }
    }
  }
}
