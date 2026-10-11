import 'package:material_ui/material_ui.dart';
import 'package:flutter/services.dart';

import '../state/code_view.dart';
import '../../l10n/l10n.dart';
import '../theme.dart';
import 'ui/toast.dart';

/// Read-only, virtualised text view with line numbers, optional JSON colours
/// and folding, and search highlighting. Rows are fixed height so a body of
/// hundreds of thousands of lines scrolls without building them all.
class CodeView extends StatefulWidget {
  const CodeView({
    super.key,
    required this.text,
    this.json = false,
    this.query = '',
    this.fontSize = 13,
    this.wrap = false,
  });

  final String text;
  final bool json;
  final String query;
  final double fontSize;

  /// Break long lines onto several rows instead of scrolling sideways. Only
  /// applies to a body within [wrapMaxLines] lines and [wrapMaxLineLength]
  /// characters per line; a larger one keeps the fixed-height rows (and the
  /// horizontal scroll) so it stays fast.
  final bool wrap;

  static const wrapMaxLines = 2000;
  static const wrapMaxLineLength = 20000;

  /// Whether [text] is small enough to wrap.
  static bool canWrap(String text) {
    final lines = splitLines(text);
    return lines.length <= wrapMaxLines &&
        lines.every((l) => l.length <= wrapMaxLineLength);
  }

  /// Row height for the default font size.
  static const rowHeight = 18.0;

  @override
  State<CodeView> createState() => _CodeViewState();
}

class _CodeViewState extends State<CodeView> {
  late List<String> _lines;
  late Map<int, int> _folds;
  final Set<int> _collapsed = {};
  late int _maxLen;
  int? _hoverRow;
  final _hScroll = ScrollController();

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _hScroll.dispose();
    super.dispose();
  }

  @override
  void didUpdateWidget(CodeView old) {
    super.didUpdateWidget(old);
    if (old.text != widget.text || old.json != widget.json) {
      _collapsed.clear();
      _load();
    }
  }

  void _load() {
    _lines = splitLines(widget.text);
    _folds = widget.json ? foldRanges(_lines) : const {};
    var m = 0;
    for (final l in _lines) {
      if (l.length > m) m = l.length;
    }
    _maxLen = m;
    _canWrap =
        _lines.length <= CodeView.wrapMaxLines &&
        m <= CodeView.wrapMaxLineLength;
  }

  late bool _canWrap;

  bool get _wrapped => widget.wrap && _canWrap;

  void _copyPath(int line) {
    final path = jsonPathForLine(_lines, line);
    if (path == null) return;
    Clipboard.setData(ClipboardData(text: path));
    showToast(context, context.l10n.codePathCopied(path));
  }

  TextSpan _span(String line, TextStyle base, ColorScheme scheme) {
    final q = widget.query.toLowerCase();
    final marks = <(int, int)>[];
    if (q.isNotEmpty) {
      final lower = line.toLowerCase();
      for (
        var i = lower.indexOf(q);
        i != -1;
        i = lower.indexOf(q, i + q.length)
      ) {
        marks.add((i, i + q.length));
      }
    }
    final tokens = widget.json ? tokenizeJsonLine(line) : const <CodeToken>[];
    if (marks.isEmpty && tokens.isEmpty) {
      return TextSpan(text: line, style: base);
    }

    // Cut the line at every token and match boundary.
    final cuts = <int>{0, line.length};
    for (final t in tokens) {
      cuts
        ..add(t.start)
        ..add(t.end);
    }
    for (final m in marks) {
      cuts
        ..add(m.$1)
        ..add(m.$2);
    }
    final points = cuts.toList()..sort();
    final spans = <InlineSpan>[];
    for (var i = 0; i < points.length - 1; i++) {
      final a = points[i], b = points[i + 1];
      var style = base;
      for (final t in tokens) {
        if (t.start <= a && b <= t.end) {
          style = base.copyWith(color: _color(t.kind, scheme));
          break;
        }
      }
      if (marks.any((m) => m.$1 <= a && b <= m.$2)) {
        style = style.copyWith(
          backgroundColor: AppColors.of(context).searchMark,
          color: AppColors.of(context).onSearchMark,
        );
      }
      spans.add(TextSpan(text: line.substring(a, b), style: style));
    }
    return TextSpan(children: spans);
  }

  Color? _color(TokenKind k, ColorScheme s) => switch (k) {
    TokenKind.key => s.primary,
    TokenKind.string => AppColors.of(context).synString,
    TokenKind.number => AppColors.of(context).synNumber,
    TokenKind.literal => AppColors.of(context).synLiteral,
    TokenKind.punct => s.onSurfaceVariant,
    TokenKind.plain => null,
  };

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final base = TextStyle(
      fontFamily: kMonoFamily,
      fontSize: widget.fontSize,
      height: 1.0,
      color: scheme.onSurface,
    );
    final rowHeight = (widget.fontSize * 1.4).ceilToDouble();
    final visible = visibleLines(_lines.length, _folds, _collapsed);
    final gutter = '${_lines.length}'.length * 8.0 + 36;
    final contentWidth = (_maxLen.clamp(1, 4000)) * widget.fontSize * 0.61 + 24;

    // Code, JSON and URLs read left to right even in a right-to-left app.
    return Directionality(
      textDirection: TextDirection.ltr,
      child: _layout(scheme, base, rowHeight, visible, gutter, contentWidth),
    );
  }

  Widget _layout(
    ColorScheme scheme,
    TextStyle base,
    double rowHeight,
    List<int> visible,
    double gutter,
    double contentWidth,
  ) {
    return LayoutBuilder(
      builder: (context, c) {
        final wrapped = _wrapped;
        final width = !wrapped && contentWidth + gutter > c.maxWidth
            ? contentWidth + gutter
            : c.maxWidth;
        // A visible bar when lines run past the edge, so wide content reads as
        // scrollable and not as cut off.
        return Scrollbar(
          controller: _hScroll,
          thumbVisibility: !wrapped && width > c.maxWidth,
          notificationPredicate: (n) => n.metrics.axis == Axis.horizontal,
          child: SingleChildScrollView(
            controller: _hScroll,
            scrollDirection: Axis.horizontal,
            child: SizedBox(
              width: width,
              child: SelectionArea(
                child: ListView.builder(
                  key: const Key('response-body'),
                  // Wrapped rows grow with their text; the others are fixed so a
                  // huge body scrolls without measuring every row.
                  itemExtent: wrapped ? null : rowHeight,
                  itemCount: visible.length,
                  itemBuilder: (context, row) {
                    final i = visible[row];
                    final foldable = _folds.containsKey(i);
                    final folded = _collapsed.contains(i);
                    return MouseRegion(
                      onEnter: (_) => setState(() => _hoverRow = i),
                      onExit: (_) {
                        if (_hoverRow == i) setState(() => _hoverRow = null);
                      },
                      child: Row(
                        crossAxisAlignment: wrapped
                            ? CrossAxisAlignment.start
                            : CrossAxisAlignment.center,
                        children: [
                          SizedBox(
                            width: gutter,
                            height: wrapped ? rowHeight : null,
                            child: Row(
                              children: [
                                SizedBox(
                                  width: 18,
                                  child: foldable
                                      ? InkWell(
                                          key: ValueKey('fold-$i'),
                                          onTap: () => setState(
                                            () => folded
                                                ? _collapsed.remove(i)
                                                : _collapsed.add(i),
                                          ),
                                          child: Icon(
                                            folded
                                                ? Icons.chevron_right
                                                : Icons.expand_more,
                                            size: 16,
                                          ),
                                        )
                                      : null,
                                ),
                                Expanded(
                                  child: SelectionContainer.disabled(
                                    child: widget.json && _hoverRow == i
                                        ? Align(
                                            alignment:
                                                AlignmentDirectional.centerEnd,
                                            child: InkWell(
                                              key: ValueKey('copy-path-$i'),
                                              onTap: () => _copyPath(i),
                                              child: Tooltip(
                                                message:
                                                    context.l10n.codeCopyPath,
                                                child: Icon(
                                                  Icons.copy,
                                                  size: 12,
                                                  color: scheme.primary,
                                                ),
                                              ),
                                            ),
                                          )
                                        : Text(
                                            '${i + 1}',
                                            textAlign: TextAlign.right,
                                            style: base.copyWith(
                                              color: scheme.outline,
                                              fontSize: 11,
                                            ),
                                          ),
                                  ),
                                ),
                                const SizedBox(width: 8),
                              ],
                            ),
                          ),
                          Expanded(
                            child: Text.rich(
                              _span(
                                folded ? '${_lines[i]} …' : _lines[i],
                                base,
                                scheme,
                              ),
                              maxLines: wrapped ? null : 1,
                              softWrap: wrapped,
                              overflow: wrapped
                                  ? TextOverflow.visible
                                  : TextOverflow.clip,
                            ),
                          ),
                        ],
                      ),
                    );
                  },
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}
