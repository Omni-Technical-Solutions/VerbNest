import 'dart:async';
import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:postit_core/postit_core.dart';
import 'package:postit_http/postit_http.dart';
import 'package:postit_storage/postit_storage.dart';

import '../scripting/script_engine.dart';
import '../scripting/script_flow.dart';
import '../scripting/script_io.dart';
import 'browser_port.dart';
import 'console_log.dart';
import 'file_port.dart';
import 'network_state.dart';
import 'prefs.dart';
import 'session.dart';
import 'settings_state.dart';
import 'variables.dart';

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
    this.tests = const [],
    this.scriptLogs = const [],
    this.scriptError,
    this.flow = const ScriptFlow(),
  });

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
    List<TestResult>? tests,
    List<ConsoleLine>? scriptLogs,
    String? scriptError,
    ScriptFlow? flow,
    bool clearResult = false,
  }) => EditorState(
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
    state = state.copyWith(item: change(state.item));
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
      var auth = effectiveAuth(item.auth, repo.authChain(id));
      if (auth is OAuth2Auth) {
        auth = await _oauthToken(auth, resolver, defaults, token);
      }
      prepared = await RequestBuilder(
        defaults: defaults,
        readFile: (ref) async =>
            repo.attachmentBytes(attachmentIdOf(ref) ?? ref),
      ).build(item, resolver, auth: auth);
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
    );
    final facts = ResponseFacts(
      status: response.status,
      headers: response.headers,
      body: response.bodyText,
      timeMs: response.timings.total.inMilliseconds,
    );
    final checks = [
      for (final a in item.assertions)
        if (a.enabled)
          a.evaluate(facts, resolve: (t) => resolver.resolve(t).value),
    ];
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

  /// Stores the exchange in local history with secrets masked (FR-HIS-001).
  /// A failure to record must never break sending.
  void _record(
    PreparedRequest p,
    String? envId, {
    HttpResponseRecord? response,
    String? error,
  }) {
    try {
      final session = ref.read(sessionProvider);
      final prefs = ref.read(prefsProvider);
      final spec = p.spec;
      ref
          .read(consoleLogProvider.notifier)
          .add(
            ConsoleEntry(
              at: DateTime.now(),
              method: spec.method,
              url: p.masker.maskText(spec.url.toString()),
              sentHead: response != null
                  ? p.masker.maskHead(response.sent.head)
                  : '${spec.method} ${p.masker.maskText(spec.url.toString())}',
              status: response?.status,
              ms: response?.timings.total.inMilliseconds,
              responseHead: response == null
                  ? null
                  : '${response.httpVersion} ${response.status} ${response.reason}\n'
                        '${response.headers.map((h) => '${h.$1}: ${h.$2}').join('\n')}',
              error: error,
            ),
          );
      final envName = envId == null
          ? null
          : session.repo
                .environments()
                .where((e) => e.id == envId)
                .firstOrNull
                ?.name;
      session.local.addHistory(
        HistoryEntry(
          id: Ulid.generate(),
          workspaceId: session.repo.workspaceId,
          requestId: id,
          method: spec.method,
          url: p.masker.maskText(spec.url.toString()),
          environmentName: envName,
          sentAt: DateTime.now(),
          status: response?.status,
          totalMs: response?.timings.total.inMilliseconds,
          requestJson: jsonEncode({
            'method': spec.method,
            'url': p.masker.maskText(spec.url.toString()),
            'headers': [
              for (final (k, v) in spec.headers)
                [k, p.masker.headerValue(k, v)],
            ],
            'body': spec.body == null || !prefs.historyBodies
                ? null
                : p.masker.maskText(
                    utf8.decode(spec.body!, allowMalformed: true),
                  ),
          }),
          responseMetaJson: response == null
              ? null
              : jsonEncode({
                  'reason': response.reason,
                  'headers': [
                    for (final (k, v) in response.headers) [k, v],
                  ],
                }),
          responseBody: response?.body,
          error: error,
        ),
        storeBodies: prefs.historyBodies,
      );
      session.local.pruneHistory(
        session.repo.workspaceId,
        maxEntries: prefs.historyMax,
        maxAge: prefs.historyDays == 0
            ? null
            : Duration(days: prefs.historyDays),
      );
      ref.read(historyTickProvider.notifier).bump();
    } catch (_) {
      // History is best-effort.
    }
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
