import 'dart:async';
import 'dart:convert';
import 'dart:io' show IOException;

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:verbnest_core/verbnest_core.dart';
import 'package:verbnest_http/verbnest_http.dart';
import 'package:verbnest_runner/verbnest_runner.dart'
    show
        HistoryRecorder,
        SecretHostNotApproved,
        evaluateAssertions,
        prepareRequest,
        requestErrorMessage;
import 'package:verbnest_script/verbnest_script.dart'
    show EngineScriptHost, ScriptHost;
import 'package:verbnest_storage/verbnest_storage.dart';

import '../scripting/script_engine.dart';
import '../scripting/script_flow.dart';
import '../scripting/script_io.dart';
import 'browser_port.dart';
import 'console_log.dart';
import 'network_state.dart';
import 'prefs.dart';
import 'session.dart';
import 'tree_state.dart';
import 'settings_state.dart';
import 'variables.dart';

enum LiveKind { websocket, sse, graphqlSubscription }

/// Replaceable in tests.
final engineProvider = Provider<HttpEngine>((ref) {
  ref.read(cookiesProvider);
  return HttpEngine(cookieJar: ref.read(cookiesProvider.notifier).jar);
});

/// Tokens fetched by OAuth 2.0 auth, kept for the app session only.
final oauthCacheProvider = Provider<OAuth2TokenCache>(
  (ref) => OAuth2TokenCache(),
);

/// What the editor tab for one request shows.
class EditorState {
  const EditorState({
    required this.item,
    this.sending = false,
    this.response,
    this.error,
    this.unresolved = const {},
    this.warnings = const [],
    this.maskedSentHead,
    this.maskedSentBody,
    this.pendingUnresolved = const {},
    this.pendingSecretHost,
    this.tests = const [],
    this.scriptLogs = const [],
    this.scriptError,
    this.flow = const ScriptFlow(),
    this.dirty = false,
  });

  /// Edits not yet written to the workspace (autosave is pending).
  final bool dirty;

  final HttpRequestItem item;
  final bool sending;
  final HttpResponseRecord? response;
  final String? error;

  /// `{{names}}` that no scope defined in the last send (FR-VAR-006).
  final Set<String> unresolved;
  final List<String> warnings;

  /// The request head as sent, with secrets masked (FR-HTTP-010).
  final String? maskedSentHead;

  /// The request body as sent, masked and capped (FR-HTTP-010).
  final String? maskedSentBody;

  /// Names that stopped a send until the user confirms.
  final Set<String> pendingUnresolved;

  /// A send stopped because secrets would go to an unapproved host.
  final SecretHostNotApproved? pendingSecretHost;

  /// Results of the post-response scripts of the last send (FR-SCR-003).
  final List<TestResult> tests;

  /// `console.*` output of the scripts of the last send.
  final List<ConsoleLine> scriptLogs;

  /// A failed post-response script; the response is still shown.
  final String? scriptError;

  /// What `pm.execution` asked of a collection run in the last send.
  final ScriptFlow flow;

  EditorState copyWith({
    HttpRequestItem? item,
    bool? sending,
    HttpResponseRecord? response,
    String? error,
    Set<String>? unresolved,
    List<String>? warnings,
    String? maskedSentHead,
    String? maskedSentBody,
    Set<String>? pendingUnresolved,
    SecretHostNotApproved? pendingSecretHost,
    bool clearSecretHost = false,
    List<TestResult>? tests,
    List<ConsoleLine>? scriptLogs,
    String? scriptError,
    ScriptFlow? flow,
    bool clearResult = false,
    bool? dirty,
  }) => EditorState(
    dirty: dirty ?? this.dirty,
    item: item ?? this.item,
    sending: sending ?? this.sending,
    response: clearResult ? null : (response ?? this.response),
    error: clearResult ? error : (error ?? this.error),
    unresolved: unresolved ?? this.unresolved,
    warnings: warnings ?? this.warnings,
    maskedSentHead: clearResult
        ? maskedSentHead
        : (maskedSentHead ?? this.maskedSentHead),
    maskedSentBody: clearResult
        ? maskedSentBody
        : (maskedSentBody ?? this.maskedSentBody),
    pendingUnresolved: clearResult
        ? (pendingUnresolved ?? const {})
        : (pendingUnresolved ?? this.pendingUnresolved),
    pendingSecretHost: clearSecretHost || clearResult
        ? pendingSecretHost
        : (pendingSecretHost ?? this.pendingSecretHost),
    tests: clearResult ? (tests ?? const []) : (tests ?? this.tests),
    scriptLogs: clearResult
        ? (scriptLogs ?? const [])
        : (scriptLogs ?? this.scriptLogs),
    scriptError: clearResult ? scriptError : (scriptError ?? this.scriptError),
    flow: clearResult ? (flow ?? const ScriptFlow()) : (flow ?? this.flow),
  );
}

/// Draft state of one open request: edits are autosaved after a short pause
/// (FR-REQ drafts) and sending works on the draft, saved or not.
class EditorNotifier extends Notifier<EditorState> {
  ScriptHost _scriptHost() => EngineScriptHost(
    ref.read(engineProvider),
    settings: ref.read(httpDefaultsProvider),
  );

  EditorNotifier(this.id);

  final String id;
  static const saveDelay = Duration(milliseconds: 500);

  Timer? _timer;
  bool _dirty = false;
  CancelToken? _cancel;

  @override
  EditorState build() {
    final repo = ref.read(repositoryProvider);
    ref.onDispose(() {
      _timer?.cancel();
      _cancel?.cancel();
      // Keep edits made in the last moments, e.g. when the workspace is
      // switched or the tab is closed before the autosave fires.
      if (_dirty) _save(repo, state.item);
    });
    return EditorState(item: repo.getRequest(id));
  }

  void edit(HttpRequestItem Function(HttpRequestItem) change) {
    state = state.copyWith(item: change(state.item), dirty: true);
    // Editing a preview tab keeps it.
    ref.read(tabsProvider.notifier).pin(id);
    _dirty = true;
    _timer?.cancel();
    _timer = Timer(saveDelay, flush);
  }

  /// Writes pending edits now. The name always comes from the tree so a
  /// rename made meanwhile is not overwritten by a stale draft.
  void flush() {
    _timer?.cancel();
    if (!_dirty) return;
    _dirty = false;
    _save(ref.read(repositoryProvider), state.item);
    state = state.copyWith(dirty: false);
  }

  void _save(WorkspaceRepository repo, HttpRequestItem item) {
    try {
      final name = repo.node(id).name;
      repo.saveRequest(item.copyWith(name: name));
    } on NotFoundError {
      // The request was deleted while it had unsaved edits.
    }
  }

  void cancel() => _cancel?.cancel();

  void dismissPending() =>
      state = state.copyWith(pendingUnresolved: const {}, clearResult: true);

  /// Remembers the host the last send was stopped for, then sends again.
  Future<void> approveSecretHostAndSend() async {
    final pending = state.pendingSecretHost;
    if (pending == null) return;
    final s = ref.read(sessionProvider);
    SecretHosts(
      s.secrets,
      s.repo.workspaceId,
    ).allow(pending.names, pending.host);
    state = state.copyWith(clearSecretHost: true);
    await send();
  }

  /// Sends the draft. With undefined variables it stops first and sets
  /// [EditorState.pendingUnresolved] unless [force] is true or the user
  /// turned the warning off.
  Future<void> send({
    bool force = false,
    Map<String, String> data = const {},
  }) async {
    if (state.sending) return;
    flush();
    final token = _cancel = CancelToken();
    state = state.copyWith(sending: true, clearResult: true);
    final session = ref.read(sessionProvider);
    final repo = session.repo;
    var item = state.item;
    final envId = ref.read(activeEnvProvider);
    PreparedRequest? prepared;
    try {
      final defaults = ref.read(httpDefaultsProvider);
      final scripts = ref.read(scriptEngineProvider);
      var local = <String, String>{};
      final pre = await runScriptPhase(
        session: session,
        engine: scripts,
        requestId: id,
        item: item,
        envId: envId,
        phase: ScriptPhase.pre,
        request: requestToMap(item),
        data: data,
        host: _scriptHost(),
      );
      local = pre.local;
      if (pre.error != null) {
        state = state.copyWith(
          sending: false,
          error: 'Pre-request script failed: ${pre.error}',
          scriptLogs: pre.logs,
        );
        return;
      }
      if (pre.request != null) item = applyRequestMap(item, pre.request!);
      if (pre.flow.skip) {
        state = state.copyWith(
          sending: false,
          scriptLogs: pre.logs,
          flow: pre.flow,
        );
        return;
      }
      final resolver = VariableResolver(
        buildScopes(
          session,
          requestId: id,
          envId: envId,
          local: local,
          data: data,
        ),
      );
      prepared = await prepareRequest(
        repo: repo,
        requestId: id,
        item: item,
        resolver: resolver,
        defaults: defaults,
        oauthToken: (auth) => _oauthToken(auth, resolver, defaults, token),
        secretHosts: SecretHosts(session.secrets, repo.workspaceId),
      );
      if (!force &&
          prepared.unresolved.isNotEmpty &&
          ref.read(warnUnresolvedProvider)) {
        state = state.copyWith(
          sending: false,
          pendingUnresolved: prepared.unresolved,
        );
        return;
      }
      final response = await sendPrepared(
        ref.read(engineProvider),
        prepared,
        cancel: token,
      );
      await _finish(
        session: session,
        item: item,
        envId: envId,
        pre: pre,
        prepared: prepared,
        response: response,
        resolver: resolver,
        data: data,
      );
      _record(prepared, envId, response: response);
    } on OAuth2Error catch (e) {
      _fail(e.message);
    } on SecretHostNotApproved catch (e) {
      state = state.copyWith(sending: false, pendingSecretHost: e);
    } on RequestBuildError catch (e) {
      _fail(e.message);
    } on HttpEngineError catch (e) {
      _fail(e.message);
      if (prepared != null) _record(prepared, envId, error: e.message);
    } finally {
      if (_cancel == token) _cancel = null;
    }
  }

  void _fail(String message) =>
      state = state.copyWith(sending: false, error: message);

  /// [e] as a [FormatException] carrying its user-facing message when it is a
  /// request failure, else [e] itself.
  Object _userFacing(Object e) {
    final message = requestErrorMessage(e);
    return message == null ? e : FormatException(message);
  }

  /// Asks this request's URL for its GraphQL schema (FR-GQL-002). Uses the
  /// request's URL, headers, auth and the active environment, but runs no
  /// scripts. Throws [FormatException] with a message fit for the user.
  Future<GraphqlSchema> introspect() async {
    flush();
    final session = ref.read(sessionProvider);
    final repo = session.repo;
    final envId = ref.read(activeEnvProvider);
    final defaults = ref.read(httpDefaultsProvider);
    final token = CancelToken();
    try {
      final resolver = VariableResolver(
        buildScopes(session, requestId: id, envId: envId),
      );
      final prepared = await prepareRequest(
        repo: repo,
        requestId: id,
        item: state.item.copyWith(
          method: 'POST',
          body: const GraphqlBody(query: graphqlIntrospectionQuery),
        ),
        resolver: resolver,
        defaults: defaults,
        oauthToken: (auth) => _oauthToken(auth, resolver, defaults, token),
        secretHosts: SecretHosts(session.secrets, repo.workspaceId),
      );
      final response = await sendPrepared(
        ref.read(engineProvider),
        prepared,
        cancel: token,
      );
      final Object? json;
      try {
        json = jsonDecode(response.bodyText);
      } on FormatException {
        throw FormatException(
          'The server answered ${response.status} and not with JSON',
        );
      }
      return GraphqlSchema.fromIntrospection(json);
    } on Object catch (e) {
      throw _userFacing(e);
    }
  }

  /// Opens a WebSocket, SSE stream or GraphQL subscription to this request's
  /// URL with its
  /// headers, auth and the active environment, running no scripts.
  /// Throws [FormatException] with a message fit for the user.
  Future<RealtimeConnection> connectRealtime(LiveKind kind) async {
    final sse = kind == LiveKind.sse;
    flush();
    final session = ref.read(sessionProvider);
    final repo = session.repo;
    final envId = ref.read(activeEnvProvider);
    final defaults = ref.read(httpDefaultsProvider);
    try {
      final resolver = VariableResolver(
        buildScopes(session, requestId: id, envId: envId),
      );
      final prepared = await prepareRequest(
        repo: repo,
        requestId: id,
        item: state.item.copyWith(
          method: kind == LiveKind.websocket ? 'GET' : state.item.method,
        ),
        resolver: resolver,
        defaults: defaults,
        oauthToken: (auth) =>
            _oauthToken(auth, resolver, defaults, CancelToken()),
        secretHosts: SecretHosts(session.secrets, repo.workspaceId),
      );
      final spec = prepared.spec;
      if (kind == LiveKind.graphqlSubscription) {
        if (state.item.body is! GraphqlBody) {
          throw const FormatException('Switch the body to graphql first');
        }
        return await connectGraphqlSubscription(
          spec.url,
          (jsonDecode(utf8.decode(spec.body ?? const [])) as Map)
              .cast<String, Object?>(),
          headers: [
            for (final h in spec.headers)
              if (h.$1.toLowerCase() != 'content-type') h,
          ],
          settings: spec.settings,
        );
      }
      return sse
          ? await connectSse(
              spec.url,
              headers: spec.headers,
              method: spec.method,
              body: spec.body,
              settings: spec.settings,
              reconnect: true,
            )
          : await connectWebSocket(
              spec.url,
              headers: [
                for (final h in spec.headers)
                  if (h.$1.toLowerCase() != 'content-type') h,
              ],
              settings: spec.settings,
            );
    } on IOException catch (e) {
      throw FormatException('$e');
    } on Object catch (e) {
      throw _userFacing(e);
    }
  }

  /// Runs the post-response script and assertions, then publishes the result.
  Future<void> _finish({
    required WorkspaceSession session,
    required HttpRequestItem item,
    required String? envId,
    required ScriptPhaseResult pre,
    required PreparedRequest prepared,
    required HttpResponseRecord response,
    required VariableResolver resolver,
    required Map<String, String> data,
  }) async {
    final post = await runScriptPhase(
      session: session,
      engine: ref.read(scriptEngineProvider),
      requestId: id,
      item: item,
      envId: envId,
      phase: ScriptPhase.post,
      request: requestToMap(item),
      response: responseToMap(response),
      local: pre.local,
      data: data,
      host: _scriptHost(),
    );
    final checks = evaluateAssertions(item, response, resolver);
    state = state.copyWith(
      sending: false,
      response: response,
      tests: [...checks, ...post.tests],
      flow: ScriptFlow(
        next: post.flow.next ?? pre.flow.next,
        stop: post.flow.stop || pre.flow.stop,
      ),
      scriptLogs: [...pre.logs, ...post.logs],
      scriptError: post.error,
      unresolved: prepared.unresolved,
      warnings: prepared.warnings,
      maskedSentHead: prepared.masker.maskHead(response.sent.head),
      maskedSentBody: describeSentBody(response.sent.body, prepared.masker),
    );
  }

  /// A bearer token for [auth], from the cache or the token endpoint.
  Future<Auth> _oauthToken(
    OAuth2Auth auth,
    VariableResolver resolver,
    HttpSettings defaults,
    CancelToken cancel,
  ) async {
    final resolved = auth.mapText((t) => resolver.resolve(t).value);
    final cache = ref.read(oauthCacheProvider);
    final engine = ref.read(engineProvider);
    var token = cache.get(resolved);
    if (token == null) {
      final stale = cache.peek(resolved);
      if (stale?.refreshToken != null) {
        try {
          token = await refreshOAuth2Token(
            engine,
            resolved,
            stale!.refreshToken!,
            cancel: cancel,
            settings: defaults,
          );
        } on OAuth2Error {
          // The refresh token was refused; sign in again below.
        }
      }
      token ??= resolved.interactive
          ? await authorizeInBrowser(
              engine,
              resolved,
              openUrl: ref.read(browserOpenerProvider),
              cancel: cancel,
              settings: defaults,
            )
          : await fetchOAuth2Token(
              engine,
              resolved,
              cancel: cancel,
              settings: defaults,
            );
      cache.put(resolved, token);
    }
    return BearerAuth(token: token.accessToken);
  }

  /// Stores the exchange in the console and in local history with secrets
  /// masked (FR-HIS-001). A failure to record must never break sending.
  void _record(
    PreparedRequest p,
    String? envId, {
    HttpResponseRecord? response,
    String? error,
  }) {
    try {
      final session = ref.read(sessionProvider);
      final prefs = ref.read(prefsProvider);
      ref
          .read(consoleLogProvider.notifier)
          .add(_consoleEntry(p, response, error));
      HistoryRecorder(
        local: session.local,
        workspaceId: session.repo.workspaceId,
        environmentName: envId == null
            ? null
            : session.repo
                  .environments()
                  .where((e) => e.id == envId)
                  .firstOrNull
                  ?.name,
        storeBodies: prefs.historyBodies,
        maxEntries: prefs.historyMax,
        maxAge: prefs.historyDays == 0
            ? null
            : Duration(days: prefs.historyDays),
      ).record(
        requestId: id,
        item: state.item,
        prepared: p,
        response: response,
        error: error,
      );
      ref.read(historyTickProvider.notifier).bump();
    } catch (_) {
      // History is best-effort.
    }
  }

  static ConsoleEntry _consoleEntry(
    PreparedRequest p,
    HttpResponseRecord? response,
    String? error,
  ) {
    final spec = p.spec;
    final url = p.masker.maskText(spec.url.toString());
    return ConsoleEntry(
      at: DateTime.now(),
      method: spec.method,
      url: url,
      sentHead: response != null
          ? p.masker.maskHead(response.sent.head)
          : '${spec.method} $url',
      status: response?.status,
      ms: response?.timings.total.inMilliseconds,
      responseHead: response == null
          ? null
          : '${response.httpVersion} ${response.status} ${response.reason}\n'
                '${response.headers.map((h) => '${h.$1}: ${h.$2}').join('\n')}',
      error: error,
    );
  }
}

final editorProvider =
    NotifierProvider.family<EditorNotifier, EditorState, String>(
      EditorNotifier.new,
    );

/// Printable, masked view of the bytes sent as the body; empty for no body.
String describeSentBody(List<int> body, Masker masker, {int cap = 65536}) {
  if (body.isEmpty) return '';
  final shown = body.length > cap ? body.sublist(0, cap) : body;
  final text = masker.maskText(utf8.decode(shown, allowMalformed: true));
  final note = body.length > cap
      ? '\n… ${body.length - cap} more bytes not shown'
      : '';
  return '$text$note';
}
