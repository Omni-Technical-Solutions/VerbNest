/// Pure helpers behind the response code view: lines, JSON tokens and folds.
library;

import 'dart:convert';

enum TokenKind { key, string, number, literal, punct, plain }

class CodeToken {
  const CodeToken(this.start, this.end, this.kind);

  final int start;
  final int end;
  final TokenKind kind;
}

List<String> splitLines(String text) => text.split('\n');

final _jsonToken = RegExp(
  r'"(?:\\.|[^"\\])*"|-?\d+(?:\.\d+)?(?:[eE][+-]?\d+)?|\btrue\b|\bfalse\b|\bnull\b|[{}\[\],:]',
);

/// Colour classes for one line of (pretty or compact) JSON.
List<CodeToken> tokenizeJsonLine(String line) {
  final out = <CodeToken>[];
  for (final m in _jsonToken.allMatches(line)) {
    final t = m[0]!;
    final kind = switch (t.codeUnitAt(0)) {
      0x22 =>
        line.startsWith(RegExp(r'\s*:'), m.end)
            ? TokenKind.key
            : TokenKind.string,
      0x74 || 0x66 || 0x6E => TokenKind.literal,
      0x7B || 0x7D || 0x5B || 0x5D || 0x2C || 0x3A => TokenKind.punct,
      _ => TokenKind.number,
    };
    out.add(CodeToken(m.start, m.end, kind));
  }
  return out;
}

/// Foldable regions of pretty-printed JSON: a line ending in `{` or `[` maps
/// to the line holding its matching closer (same indent).
Map<int, int> foldRanges(List<String> lines) {
  final out = <int, int>{};
  final stack = <(int line, int indent)>[];
  for (var i = 0; i < lines.length; i++) {
    final line = lines[i];
    final trimmed = line.trimRight();
    if (trimmed.isEmpty) continue;
    final indent = line.length - line.trimLeft().length;
    final first = trimmed.trimLeft()[0];
    if ((first == '}' || first == ']') && stack.isNotEmpty) {
      final open = stack.removeLast();
      out[open.$1] = i;
    }
    final last = trimmed[trimmed.length - 1];
    if (last == '{' || last == '[') stack.add((i, indent));
  }
  return out;
}

/// Line indices to show given the [collapsed] fold starts.
List<int> visibleLines(int total, Map<int, int> folds, Set<int> collapsed) {
  if (collapsed.isEmpty) return List.generate(total, (i) => i);
  final out = <int>[];
  var i = 0;
  while (i < total) {
    out.add(i);
    // A folded region jumps to its closing line, which stays visible.
    i = collapsed.contains(i) && folds.containsKey(i) ? folds[i]! : i + 1;
  }
  return out;
}

class _Frame {
  _Frame(this.path, this.isArray);

  final String path;
  final bool isArray;
  int count = 0;
}

final _keyAtStart = RegExp(r'^"((?:\\.|[^"\\])*)"\s*:');
final _plainKey = RegExp(r'^[A-Za-z_]\w*$');

String _child(String parent, String key) =>
    _plainKey.hasMatch(key) ? '$parent.$key' : "$parent['$key']";

/// JSONPath of the value written on line [index] of pretty-printed JSON, for
/// example `$.items[2].name`. A closing bracket gives the path of the
/// container it closes. Returns null when [index] is out of range or blank.
String? jsonPathForLine(List<String> lines, int index) {
  final stack = <_Frame>[];
  for (var i = 0; i <= index && i < lines.length; i++) {
    final t = lines[i].trim();
    if (t.isEmpty) {
      if (i == index) return null;
      continue;
    }
    if (t[0] == '}' || t[0] == ']') {
      final closed = stack.isEmpty ? null : stack.removeLast();
      if (i == index) return closed?.path ?? r'$';
      continue;
    }
    String here;
    if (stack.isEmpty) {
      here = r'$';
    } else if (stack.last.isArray) {
      here = '${stack.last.path}[${stack.last.count++}]';
    } else {
      final m = _keyAtStart.firstMatch(t);
      var key = m?[1];
      if (key != null) {
        try {
          key = jsonDecode('"$key"') as String;
        } on FormatException {
          // Keep the raw text.
        }
      }
      here = key == null ? stack.last.path : _child(stack.last.path, key);
    }
    if (i == index) return here;
    final last = t[t.length - 1];
    if (last == '{' || last == '[') stack.add(_Frame(here, last == '['));
  }
  return null;
}
