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
    this.scriptsTrusted = false,
    this.accent = 0,
    this.compact = false,
  });

  /// Entries older than this are removed; 0 keeps them forever.
  final int historyDays;
  final int historyMax;

  /// False records only the request line and headers, not bodies.
  final bool historyBodies;
  final double fontScale;
  final double editorFontSize;

  /// Whether scripts in this workspace may run. Off by default so imported or
  /// shared workspaces cannot run code until the user allows it.
  final bool scriptsTrusted;

  /// Index into `AppAccents.seeds`.
  final int accent;

  /// Tighter spacing for dense screens.
  final bool compact;

  static const minScale = 0.8, maxScale = 1.6;
  static const minEditorSize = 10.0, maxEditorSize = 24.0;

  Prefs copyWith({
    int? historyDays,
    int? historyMax,
    bool? historyBodies,
    double? fontScale,
    double? editorFontSize,
    bool? scriptsTrusted,
    int? accent,
    bool? compact,
  }) => Prefs(
    historyDays: historyDays ?? this.historyDays,
    historyMax: historyMax ?? this.historyMax,
    historyBodies: historyBodies ?? this.historyBodies,
    fontScale: (fontScale ?? this.fontScale).clamp(minScale, maxScale),
    editorFontSize: (editorFontSize ?? this.editorFontSize).clamp(
      minEditorSize,
      maxEditorSize,
    ),
    scriptsTrusted: scriptsTrusted ?? this.scriptsTrusted,
    accent: accent ?? this.accent,
    compact: compact ?? this.compact,
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
      scriptsTrusted: get('scriptsTrusted') == 'true',
      accent: int.tryParse(get('accent') ?? ''),
      compact: get('compact') == 'true',
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
    put('scriptsTrusted', next.scriptsTrusted);
    put('accent', next.accent);
    put('compact', next.compact);
    state = next;
  }
}

final prefsProvider = NotifierProvider<PrefsNotifier, Prefs>(PrefsNotifier.new);

/// Where the divider sits between request and response, and whether they
/// sit side by side. Stored with the other device-local preferences.
class SplitLayout {
  const SplitLayout({this.ratio = 0.5, this.horizontal});

  final double ratio;

  /// Null until the user picks a direction; the editor then chooses by width
  /// (side by side when it is wide enough, stacked otherwise).
  final bool? horizontal;

  static const minRatio = 0.15, maxRatio = 0.85;

  SplitLayout copyWith({double? ratio, bool? horizontal}) => SplitLayout(
    ratio: (ratio ?? this.ratio).clamp(minRatio, maxRatio),
    horizontal: horizontal ?? this.horizontal,
  );
}

class SplitLayoutNotifier extends Notifier<SplitLayout> {
  @override
  SplitLayout build() {
    final s = ref.read(sessionProvider);
    final ws = s.repo.workspaceId;
    String? get(String k) => s.local.kv(ws, 'pref.$k');
    return const SplitLayout().copyWith(
      ratio: double.tryParse(get('splitRatio') ?? ''),
      horizontal: switch (get('splitHorizontal')) {
        'true' => true,
        'false' => false,
        _ => null,
      },
    );
  }

  void update(SplitLayout next) {
    final s = ref.read(sessionProvider);
    final ws = s.repo.workspaceId;
    s.local.setKv(ws, 'pref.splitRatio', '${next.ratio}');
    if (next.horizontal != null) {
      s.local.setKv(ws, 'pref.splitHorizontal', '${next.horizontal}');
    }
    state = next;
  }
}

final splitLayoutProvider = NotifierProvider<SplitLayoutNotifier, SplitLayout>(
  SplitLayoutNotifier.new,
);
