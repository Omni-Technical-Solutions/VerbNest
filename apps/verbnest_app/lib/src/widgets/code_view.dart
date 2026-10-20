import 'package:material_ui/material_ui.dart';

import 'ui/still_scrollbar.dart';

import 'package:flutter/services.dart';

import '../state/code_view.dart';
import '../../l10n/l10n.dart';
import '../theme.dart';
import 'ui/toast.dart';
import 'ui/still_tooltip.dart';

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

  /// The row under the pointer. A notifier, so hovering repaints one gutter and
  /// never rebuilds the list, and it is only set by pointer movement, not by
  /// rows passing under a pointer that is still (wheel and trackpad scrolling).
  final _hover = ValueNotifier<int?>(null);
  bool _scrolling = false;
  final _hScroll = ScrollController();

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _hover.dispose();
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

  /// Lines longer than this are not syntax coloured.
  static const _maxColouredLine = 5000;

  /// Search matches marked on one line.
  static const _maxMarksPerLine = 500;

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
        // A giant line gets only its first matches marked: each one costs a
        // text span, and thousands of spans make the line slow to lay out.
        if (marks.length >= _maxMarksPerLine) break;
      }
    }
    // A line of tens of thousands of characters (minified or invalid JSON) is
    // drawn plain: colouring it would build one span per token, and the text
    // layout of that is slower than the rest of the app put together.
    final tokens = widget.json && line.length <= _maxColouredLine
        ? tokenizeJsonLine(line)
        : const <CodeToken>[];
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
    // Tokens and matches are in order and the cuts ascend, so one pass over
    // each finds the token and match under a segment (a scan of all of them
    // per segment is quadratic in the line length).
    var ti = 0, mi = 0;
    for (var i = 0; i < points.length - 1; i++) {
      final a = points[i], b = points[i + 1];
      var style = base;
      while (ti < tokens.length && tokens[ti].end <= a) {
        ti++;
      }
      if (ti < tokens.length && tokens[ti].start <= a && b <= tokens[ti].end) {
        style = base.copyWith(color: _color(tokens[ti].kind, scheme));
      }
      while (mi < marks.length && marks[mi].$2 <= a) {
        mi++;
      }
      if (mi < marks.length && marks[mi].$1 <= a && b <= marks[mi].$2) {
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

  /// One line of the body: the fold control and line number (or the copy-path
  /// button under the pointer), then the highlighted text.
  Widget _row(
    BuildContext context,
    int i,
    TextStyle base,
    ColorScheme scheme,
    double gutter,
    double rowHeight,
    bool wrapped,
  ) {
    final foldable = _folds.containsKey(i);
    final folded = _collapsed.contains(i);
    return MouseRegion(
      // Movement, not entering: a row that scrolls under a
      // still pointer is not hovered.
      onHover: (_) {
        if (!_scrolling) _hover.value = i;
      },
      onExit: (_) {
        if (_hover.value == i) _hover.value = null;
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
                            folded ? Icons.chevron_right : Icons.expand_more,
                            size: 16,
                          ),
                        )
                      : null,
                ),
                Expanded(
                  child: SelectionContainer.disabled(
                    child: ValueListenableBuilder<int?>(
                      valueListenable: _hover,
                      builder: (context, hovered, _) =>
                          widget.json && hovered == i
                          ? Align(
                              alignment: AlignmentDirectional.centerEnd,
                              child: InkWell(
                                key: ValueKey('copy-path-$i'),
                                onTap: () => _copyPath(i),
                                child: StillTooltip(
                                  message: context.l10n.codeCopyPath,
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
                ),
                const SizedBox(width: 8),
              ],
            ),
          ),
          Expanded(
            child: Text.rich(
              _span(folded ? '${_lines[i]} …' : _lines[i], base, scheme),
              maxLines: wrapped ? null : 1,
              softWrap: wrapped,
              overflow: wrapped ? TextOverflow.visible : TextOverflow.clip,
            ),
          ),
        ],
      ),
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
        return StillScrollbar(
          controller: _hScroll,
          thumbVisibility: !wrapped && width > c.maxWidth,
          axis: Axis.horizontal,
          notificationPredicate: (n) => n.metrics.axis == Axis.horizontal,
          child: SingleChildScrollView(
            controller: _hScroll,
            scrollDirection: Axis.horizontal,
            child: SizedBox(
              width: width,
              child: SelectionArea(
                child: NotificationListener<ScrollNotification>(
                  onNotification: _onScroll,
                  child: ListView.builder(
                    key: const Key('response-body'),
                    // No rubber-band at the ends: the content only moves with
                    // the scroll, nothing springs back.
                    physics: const ClampingScrollPhysics(),
                    // Wrapped rows grow with their text; the others are fixed so a
                    // huge body scrolls without measuring every row.
                    itemExtent: wrapped ? null : rowHeight,
                    itemCount: visible.length,
                    itemBuilder: (context, row) => _row(
                      context,
                      visible[row],
                      base,
                      scheme,
                      gutter,
                      rowHeight,
                      wrapped,
                    ),
                  ),
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  /// No row is hovered while the list moves: rows slide under a pointer that
  /// has not moved, and swapping their line number for an icon would flicker.
  bool _onScroll(ScrollNotification n) {
    if (n.metrics.axis != Axis.vertical) return false;
    if (n is ScrollStartNotification || n is ScrollUpdateNotification) {
      _scrolling = true;
      if (_hover.value != null) _hover.value = null;
    } else if (n is ScrollEndNotification) {
      _scrolling = false;
    }
    return false;
  }
}
