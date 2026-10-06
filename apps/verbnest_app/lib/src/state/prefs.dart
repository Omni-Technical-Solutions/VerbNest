import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'session.dart';

/// Device-local preferences (FR-APP-002, FR-HIS-003). They live in the local
/// database, not in the workspace file, so sharing a workspace never changes
/// somebody else's fonts or history limits.
class Prefs {
  const Prefs({
    this.historyDays = 90,
    this.historyMax = 1000,
    this.historyBodies = true,
    this.fontScale = 1.0,
    this.editorFontSize = 13,
  });

  /// Entries older than this are removed; 0 keeps them forever.
  final int historyDays;
  final int historyMax;

  /// False records only the request line and headers, not bodies.
  final bool historyBodies;
  final double fontScale;
  final double editorFontSize;

  static const minScale = 0.8, maxScale = 1.6;
  static const minEditorSize = 10.0, maxEditorSize = 24.0;

  Prefs copyWith({
    int? historyDays,
    int? historyMax,
    bool? historyBodies,
    double? fontScale,
    double? editorFontSize,
  }) => Prefs(
    historyDays: historyDays ?? this.historyDays,
    historyMax: historyMax ?? this.historyMax,
    historyBodies: historyBodies ?? this.historyBodies,
    fontScale: (fontScale ?? this.fontScale).clamp(minScale, maxScale),
    editorFontSize: (editorFontSize ?? this.editorFontSize).clamp(
      minEditorSize,
      maxEditorSize,
    ),
  );
}

class PrefsNotifier extends Notifier<Prefs> {
  @override
  Prefs build() {
    final s = ref.read(sessionProvider);
    final ws = s.repo.workspaceId;
    String? get(String k) => s.local.kv(ws, 'pref.$k');
    const d = Prefs();
    return d.copyWith(
      historyDays: int.tryParse(get('historyDays') ?? ''),
      historyMax: int.tryParse(get('historyMax') ?? ''),
      historyBodies: get('historyBodies') == null
          ? null
          : get('historyBodies') == 'true',
      fontScale: double.tryParse(get('fontScale') ?? ''),
      editorFontSize: double.tryParse(get('editorFontSize') ?? ''),
    );
  }

  void update(Prefs next) {
    final s = ref.read(sessionProvider);
    final ws = s.repo.workspaceId;
    void put(String k, Object v) => s.local.setKv(ws, 'pref.$k', '$v');
    put('historyDays', next.historyDays);
    put('historyMax', next.historyMax);
    put('historyBodies', next.historyBodies);
    put('fontScale', next.fontScale);
    put('editorFontSize', next.editorFontSize);
    state = next;
  }
}

final prefsProvider = NotifierProvider<PrefsNotifier, Prefs>(PrefsNotifier.new);
