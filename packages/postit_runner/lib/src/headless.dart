import 'dart:io' show IOException;

import 'package:postit_core/postit_core.dart';
import 'package:postit_http/postit_http.dart';
import 'package:postit_storage/postit_storage.dart';

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

  final containers = repo.ancestors(requestId).reversed.toList();
  return VariableScopes(
    local: [
      for (final e in overrides.entries) Variable(key: e.key, value: e.value),
    ],
    data: [for (final e in data.entries) Variable(key: e.key, value: e.value)],
    global: vars(VariableOwner.global),
    environment: envId == null
        ? const []
        : vars(VariableOwner.environment(envId)),
    collection: [
      for (var i = 0; i < containers.length; i++)
        ...vars(
          i == 0
              ? VariableOwner.collection(containers[i])
              : VariableOwner.folder(containers[i]),
        ),
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
    OAuth2TokenCache? oauthCache,
  }) : _oauthCache = oauthCache ?? OAuth2TokenCache();

  final WorkspaceRepository repo;
  final HttpEngine engine;
  final HttpSettings defaults;
  final String? envId;

  /// Highest-precedence variables, like `--var name=value`.
  final Map<String, String> overrides;
  final SecretStore? secrets;
  final OAuth2TokenCache _oauthCache;

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
      );

  static String? _attachmentId(String ref) {
    if (!ref.startsWith('attachment:')) return null;
    final rest = ref.substring('attachment:'.length);
    final slash = rest.indexOf('/');
    return slash < 0 ? rest : rest.substring(0, slash);
  }

  /// A [RunStep] for [executeRun].
  Future<RunStepResult> step(
    String id,
    String name,
    int iteration,
    Map<String, String> row,
  ) async {
    final item = repo.getRequest(id);
    if (!item.scripts.isEmpty || repo.scriptsChain(id).any((s) => !s.isEmpty)) {
      scriptsSkipped.add(name);
    }
    RunEntry entry({
      HttpResponseRecord? response,
      List<TestResult> tests = const [],
      String? error,
    }) => RunEntry(
      iteration: iteration,
      requestId: id,
      name: name,
      method: item.method,
      url: response?.sent.url.toString() ?? item.url,
      status: response?.status,
      reason: response?.reason ?? '',
      timeMs: response?.timings.total.inMilliseconds ?? 0,
      tests: tests,
      error: error,
    );
    try {
      final resolver = VariableResolver(scopesFor(id, row));
      var auth = effectiveAuth(item.auth, repo.authChain(id));
      if (auth is OAuth2Auth) {
        auth = await _oauthToken(auth, resolver);
      }
      final prepared = await RequestBuilder(
        defaults: defaults,
        readFile: (ref) async =>
            repo.attachmentBytes(_attachmentId(ref) ?? ref),
      ).build(item, resolver, auth: auth);
      final response = await sendPrepared(engine, prepared);
      final facts = ResponseFacts(
        status: response.status,
        headers: response.headers,
        body: response.bodyText,
        timeMs: response.timings.total.inMilliseconds,
      );
      return RunStepResult(
        entry(
          response: response,
          tests: [
            for (final a in item.assertions)
              if (a.enabled)
                a.evaluate(facts, resolve: (t) => resolver.resolve(t).value),
          ],
        ),
      );
    } on OAuth2Error catch (e) {
      return RunStepResult(entry(error: e.message));
    } on RequestBuildError catch (e) {
      return RunStepResult(entry(error: e.message));
    } on HttpEngineError catch (e) {
      return RunStepResult(entry(error: e.message));
    } on IOException catch (e) {
      return RunStepResult(entry(error: '$e'));
    }
  }

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
