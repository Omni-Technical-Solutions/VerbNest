import 'dart:async';
import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:postit_core/postit_core.dart';
import 'package:postit_http/postit_http.dart';
import 'package:postit_storage/postit_storage.dart';

import 'file_port.dart';
import 'session.dart';
import 'settings_state.dart';
import 'variables.dart';

/// Replaceable in tests.
final engineProvider = Provider<HttpEngine>((ref) => HttpEngine());

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
  Future<void> send({bool force = false}) async {
    if (state.sending) return;
    flush();
    final token = _cancel = CancelToken();
    state = state.copyWith(sending: true, clearResult: true);
    final session = ref.read(sessionProvider);
    final repo = session.repo;
    final item = state.item;
    final envId = ref.read(activeEnvProvider);
    PreparedRequest? prepared;
    try {
      final defaults = ref.read(httpDefaultsProvider);
      final resolver = VariableResolver(
        buildScopes(session, requestId: id, envId: envId),
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
      final response = await ref
          .read(engineProvider)
          .send(prepared.spec, cancel: token);
      state = state.copyWith(
        sending: false,
        response: response,
        unresolved: prepared.unresolved,
        warnings: prepared.warnings,
        maskedSentHead: prepared.masker.maskHead(response.sent.head),
        maskedSentBody: describeSentBody(response.sent.body, prepared.masker),
      );
      _record(prepared, envId, response: response);
    } on OAuth2Error catch (e) {
      state = state.copyWith(sending: false, error: e.message);
    } on RequestBuildError catch (e) {
      state = state.copyWith(sending: false, error: e.message);
    } on HttpEngineError catch (e) {
      state = state.copyWith(sending: false, error: e.message);
      if (prepared != null) _record(prepared, envId, error: e.message);
    } finally {
      if (_cancel == token) _cancel = null;
    }
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
    var token = cache.get(resolved);
    if (token == null) {
      token = await fetchOAuth2Token(
        ref.read(engineProvider),
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
      final spec = p.spec;
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
            'body': spec.body == null
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
