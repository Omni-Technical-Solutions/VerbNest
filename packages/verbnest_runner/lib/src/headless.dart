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
  // An override of a secret variable stays secret, so reports and history
  // mask its value and the approved-host check applies to it.
  final secretKeys = {
    for (final o in [
      VariableOwner.global,
      if (envId != null) VariableOwner.environment(envId),
      for (var i = 0; i < containers.length; i++)
        i == 0
            ? VariableOwner.collection(containers[i])
            : VariableOwner.folder(containers[i]),
    ])
      for (final v in repo.variables(o))
        if (v.secret) v.key,
  };
  return VariableScopes(
    local: [
      for (final e in overrides.entries)
        Variable(
          key: e.key,
          value: e.value,
          secret: secretKeys.contains(e.key),
        ),
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
  ) => _StepRun(this, id, name, iteration, row).run();

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

/// One run of one request: pre-request script, send, assertions, post-response
/// script. Holds the state those phases share.
class _StepRun {
  _StepRun(this._h, this.id, this.name, this.iteration, this.row)
    : item = _h.repo.getRequest(id) {
    hasScripts =
        !item.scripts.isEmpty ||
        _h.repo.scriptsChain(id).any((s) => !s.isEmpty);
    if (hasScripts && _h.scripts == null) _h.scriptsSkipped.add(name);
  }

  final HeadlessSender _h;
  final String id;
  final String name;
  final int iteration;
  final Map<String, String> row;

  HttpRequestItem item;
  late final bool hasScripts;
  final logs = <ConsoleLine>[];
  PreparedRequest? _sent;
  Map<String, String> _local = {};
  ScriptFlow _flow = const ScriptFlow();

  /// The script engine, when there is one and this request has scripts.
  ScriptEngine? get _scriptEngine => hasScripts ? _h.scripts : null;

  RunEntry _entry({
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
        : _sent?.masker.maskText(response.sent.url.toString()) ??
              response.sent.url.toString(),
    status: response?.status,
    reason: response?.reason ?? '',
    timeMs: response?.timings.total.inMilliseconds ?? 0,
    tests: tests,
    error: error,
  );

  Future<RunStepResult> run() async {
    try {
      final early = await _pre();
      if (early != null) return early;
      final resolver = VariableResolver(
        workspaceScopes(
          _h.repo,
          id,
          envId: _h.envId,
          overrides: {..._h.overrides, ..._local},
          data: row,
          secrets: _h.secrets,
          scriptValues: _h._scriptVars.state,
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
        repo: _h.repo,
        requestId: id,
        item: item,
        resolver: resolver,
        defaults: _h.defaults,
        oauthToken: (auth) => _h._oauthToken(auth, resolver),
        secretHosts: _h.secrets == null
            ? null
            : SecretHosts(
                _h.secrets!,
                _h.repo.workspaceId,
                extra: _h.secretHostFlags,
              ),
      );
      _sent = prepared;
      final response = await sendPrepared(_h.engine, prepared);
      _h.history?.record(
        requestId: id,
        item: item,
        prepared: prepared,
        response: response,
      );
      final tests = evaluateAssertions(item, response, resolver);
      final scriptError = await _post(response, tests);
      _h.lastLogs[id] = logs;
      return RunStepResult(
        _entry(response: response, tests: tests, error: scriptError),
        RunFlow(next: _flow.next, stop: _flow.stop),
      );
    } on OAuth2Error catch (e) {
      return RunStepResult(_entry(error: e.message));
    } on RequestBuildError catch (e) {
      return RunStepResult(_entry(error: e.message));
    } on HttpEngineError catch (e) {
      _recordFailure(e.message);
      return RunStepResult(_entry(error: e.message));
    } on IOException catch (e) {
      _recordFailure('$e');
      return RunStepResult(_entry(error: '$e'));
    }
  }

  void _recordFailure(String message) => _h.history?.record(
    requestId: id,
    item: item,
    prepared: _sent,
    error: message,
  );

  /// Runs the pre-request script. Returns the result that ends this step early
  /// (a script error or a skip), or null to go on and send.
  Future<RunStepResult?> _pre() async {
    final engine = _scriptEngine;
    if (engine == null) return null;
    final pre = await runScriptPhaseWith(
      repo: _h.repo,
      variables: _h._scriptVars,
      engine: engine,
      requestId: id,
      item: item,
      envId: _h.envId,
      phase: ScriptPhase.pre,
      request: requestToMap(item),
      data: row,
      host: _h._scriptHost,
    );
    _local = pre.local;
    logs.addAll(pre.logs);
    if (pre.error != null) {
      return RunStepResult(
        _entry(error: 'Pre-request script failed: ${pre.error}'),
        RunFlow(next: pre.flow.next, stop: pre.flow.stop),
      );
    }
    if (pre.request != null) item = applyRequestMap(item, pre.request!);
    _flow = pre.flow;
    if (_flow.skip) {
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
        RunFlow(next: _flow.next, stop: _flow.stop, skip: true),
      );
    }
    return null;
  }

  /// Runs the post-response script, adds its tests, and returns its error
  /// text (or null).
  Future<String?> _post(
    HttpResponseRecord response,
    List<TestResult> tests,
  ) async {
    final engine = _scriptEngine;
    if (engine == null) return null;
    final post = await runScriptPhaseWith(
      repo: _h.repo,
      variables: _h._scriptVars,
      engine: engine,
      requestId: id,
      item: item,
      envId: _h.envId,
      phase: ScriptPhase.post,
      request: requestToMap(item),
      response: responseToMap(response),
      local: _local,
      data: row,
      host: _h._scriptHost,
    );
    tests.addAll(post.tests);
    logs.addAll(post.logs);
    _flow = ScriptFlow(
      next: post.flow.next ?? _flow.next,
      stop: post.flow.stop || _flow.stop,
    );
    return post.error == null
        ? null
        : 'Post-response script failed: ${post.error}';
  }
}
