import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:postit_core/postit_core.dart';
import 'package:postit_http/postit_http.dart';
import 'package:postit_storage/postit_storage.dart';

import 'session.dart';

/// Replaceable in tests.
final engineProvider = Provider<HttpEngine>((ref) => HttpEngine());

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

  EditorState copyWith({
    HttpRequestItem? item,
    bool? sending,
    HttpResponseRecord? response,
    String? error,
    Set<String>? unresolved,
    List<String>? warnings,
    String? maskedSentHead,
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
    ref.onDispose(() {
      _timer?.cancel();
      _cancel?.cancel();
    });
    return EditorState(item: ref.read(repositoryProvider).getRequest(id));
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
    final repo = ref.read(repositoryProvider);
    try {
      final name = repo.node(id).name;
      repo.saveRequest(state.item.copyWith(name: name));
    } on NotFoundError {
      // The request was deleted while it had unsaved edits.
    }
  }

  void cancel() => _cancel?.cancel();

  Future<void> send() async {
    if (state.sending) return;
    flush();
    final token = _cancel = CancelToken();
    state = state.copyWith(sending: true, clearResult: true);
    try {
      final repo = ref.read(repositoryProvider);
      final item = state.item;
      final prepared = await RequestBuilder().build(
        item,
        VariableResolver(_scopes(repo)),
        auth: effectiveAuth(item.auth, repo.authChain(id)),
      );
      final response = await ref
          .read(engineProvider)
          .send(prepared.spec, cancel: token);
      state = state.copyWith(
        sending: false,
        response: response,
        unresolved: prepared.unresolved,
        warnings: prepared.warnings,
        maskedSentHead: prepared.masker.maskHead(response.sent.head),
      );
    } on RequestBuildError catch (e) {
      state = state.copyWith(sending: false, error: e.message);
    } on HttpEngineError catch (e) {
      state = state.copyWith(sending: false, error: e.message);
    } finally {
      if (_cancel == token) _cancel = null;
    }
  }

  VariableScopes _scopes(WorkspaceRepository repo) {
    final containers = repo.ancestors(id).reversed.toList(); // root first
    return VariableScopes(
      global: repo.variables(VariableOwner.global),
      collection: [
        for (var i = 0; i < containers.length; i++)
          ...repo.variables(
            i == 0
                ? VariableOwner.collection(containers[i])
                : VariableOwner.folder(containers[i]),
          ),
      ],
    );
  }
}

final editorProvider =
    NotifierProvider.family<EditorNotifier, EditorState, String>(
      EditorNotifier.new,
    );
