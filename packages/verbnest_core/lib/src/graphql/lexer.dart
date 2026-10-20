/// Lexical tokens shared by the SDL parser and query completion.
enum GqlTok { punct, name, string, blockString, number, variable, spread, end }

class GqlToken {
  const GqlToken(this.kind, this.text, this.start, this.end);

  final GqlTok kind;

  /// For strings and block strings this is the decoded content; for others the
  /// source text.
  final String text;
  final int start;
  final int end;

  bool isPunct(String p) => kind == GqlTok.punct && text == p;
  bool isName(String n) => kind == GqlTok.name && text == n;

  @override
  String toString() => '$kind($text)';
}

/// Result of lexing: the tokens, and whether the input stopped inside an
/// unfinished string (completion must stay quiet there).
class GqlLexed {
  const GqlLexed(this.tokens, {this.openString = false});

  final List<GqlToken> tokens;
  final bool openString;
}

const _punct = '!()[]{}:=@|&';

/// Splits GraphQL source into tokens. Commas, spaces and `#` comments are
/// skipped. Never throws; unknown characters are skipped.
GqlLexed lexGraphql(String src) {
  final out = <GqlToken>[];
  var i = 0;
  final n = src.length;
  while (i < n) {
    final c = src.codeUnitAt(i);
    if (_isBlank(c)) {
      i++;
    } else if (c == 35) {
      i = _skipComment(src, i);
    } else if (c == 34) {
      final tok = src.startsWith('"""', i)
          ? _lexBlockString(src, i)
          : _lexString(src, i);
      if (tok == null) return GqlLexed(out, openString: true);
      out.add(tok);
      i = tok.end;
    } else {
      final tok = _lexSimple(src, i, c);
      if (tok == null) {
        i++;
      } else {
        out.add(tok);
        i = tok.end;
      }
    }
  }
  return GqlLexed(out);
}

bool _isBlank(int c) =>
    c == 32 || c == 9 || c == 10 || c == 13 || c == 44 || c == 0xFEFF;

bool _isNameStart(int c) =>
    (c >= 65 && c <= 90) || (c >= 97 && c <= 122) || c == 95;

bool _isNamePart(int c) => _isNameStart(c) || (c >= 48 && c <= 57);

int _skipComment(String src, int i) {
  while (i < src.length && src.codeUnitAt(i) != 10) {
    i++;
  }
  return i;
}

final _numberChar = RegExp(r'[0-9.eE+\-]');

/// The spread, punctuation, variable, name or number starting at [i], or null
/// for a character that is skipped.
GqlToken? _lexSimple(String src, int i, int c) {
  if (src.startsWith('...', i)) {
    return GqlToken(GqlTok.spread, '...', i, i + 3);
  }
  if (_punct.contains(src[i])) return GqlToken(GqlTok.punct, src[i], i, i + 1);
  if (c == 36) return _lexRun(src, i, GqlTok.variable);
  if (_isNameStart(c)) return _lexRun(src, i, GqlTok.name);
  if ((c >= 48 && c <= 57) || c == 45) {
    var j = i + 1;
    while (j < src.length && _numberChar.hasMatch(src[j])) {
      j++;
    }
    return GqlToken(GqlTok.number, src.substring(i, j), i, j);
  }
  return null;
}

GqlToken _lexRun(String src, int i, GqlTok kind) {
  var j = i + 1;
  while (j < src.length && _isNamePart(src.codeUnitAt(j))) {
    j++;
  }
  return GqlToken(kind, src.substring(i, j), i, j);
}

/// A `"""` block string starting at [start], or null if it never closes.
GqlToken? _lexBlockString(String src, int start) {
  var j = start + 3;
  final buf = StringBuffer();
  while (j < src.length) {
    if (src.startsWith(r'\"""', j)) {
      buf.write('"""');
      j += 4;
    } else if (src.startsWith('"""', j)) {
      return GqlToken(
        GqlTok.blockString,
        _dedent(buf.toString()),
        start,
        j + 3,
      );
    } else {
      buf.write(src[j]);
      j++;
    }
  }
  return null;
}

/// A single-line string starting at [start], or null if it never closes.
GqlToken? _lexString(String src, int start) {
  var j = start + 1;
  final n = src.length;
  final buf = StringBuffer();
  while (j < n && src[j] != '\n') {
    if (src[j] == r'\' && j + 1 < n) {
      final e = src[j + 1];
      buf.write(switch (e) {
        'n' => '\n',
        't' => '\t',
        'r' => '\r',
        _ => e,
      });
      j += 2;
    } else if (src[j] == '"') {
      return GqlToken(GqlTok.string, buf.toString(), start, j + 1);
    } else {
      buf.write(src[j]);
      j++;
    }
  }
  return null;
}

/// Removes the common indentation of a block string, as the spec asks.
String _dedent(String raw) {
  final lines = raw.split(RegExp(r'\r\n|\n|\r'));
  var common = -1;
  for (final l in lines.skip(1)) {
    final indent = l.length - l.trimLeft().length;
    if (l.trim().isEmpty) continue;
    if (common == -1 || indent < common) common = indent;
  }
  final out = [
    lines.first,
    for (final l in lines.skip(1))
      common > 0 && l.length >= common ? l.substring(common) : l.trimLeft(),
  ];
  while (out.isNotEmpty && out.first.trim().isEmpty) {
    out.removeAt(0);
  }
  while (out.isNotEmpty && out.last.trim().isEmpty) {
    out.removeLast();
  }
  return out.join('\n');
}
