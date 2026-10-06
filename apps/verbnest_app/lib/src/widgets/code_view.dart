import 'package:flutter/material.dart';

import '../state/code_view.dart';

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
  });

  final String text;
  final bool json;
  final String query;
  final double fontSize;

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

  @override
  void initState() {
    super.initState();
    _load();
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
          backgroundColor: const Color(0xFFFFE082),
          color: Colors.black,
        );
      }
      spans.add(TextSpan(text: line.substring(a, b), style: style));
    }
    return TextSpan(children: spans);
  }

  Color? _color(TokenKind k, ColorScheme s) => switch (k) {
    TokenKind.key => s.primary,
    TokenKind.string => Colors.green.shade700,
    TokenKind.number => Colors.orange.shade800,
    TokenKind.literal => Colors.purple.shade400,
    TokenKind.punct => s.onSurfaceVariant,
    TokenKind.plain => null,
  };

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final base = TextStyle(
      fontFamily: 'monospace',
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
        final width = contentWidth + gutter > c.maxWidth
            ? contentWidth + gutter
            : c.maxWidth;
        return SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: SizedBox(
            width: width,
            child: SelectionArea(
              child: ListView.builder(
                key: const Key('response-body'),
                itemExtent: rowHeight,
                itemCount: visible.length,
                itemBuilder: (context, row) {
                  final i = visible[row];
                  final foldable = _folds.containsKey(i);
                  final folded = _collapsed.contains(i);
                  return Row(
                    children: [
                      SizedBox(
                        width: gutter,
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
                                child: Text(
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
                          maxLines: 1,
                          softWrap: false,
                          overflow: TextOverflow.clip,
                        ),
                      ),
                    ],
                  );
                },
              ),
            ),
          ),
        );
      },
    );
  }
}
