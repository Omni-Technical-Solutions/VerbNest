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
  bool isStart(int c) =>
      (c >= 65 && c <= 90) || (c >= 97 && c <= 122) || c == 95;
  bool isPart(int c) => isStart(c) || (c >= 48 && c <= 57);
  while (i < n) {
    final c = src.codeUnitAt(i);
    if (c == 32 || c == 9 || c == 10 || c == 13 || c == 44 || c == 0xFEFF) {
      i++;
    } else if (c == 35) {
      while (i < n && src.codeUnitAt(i) != 10) {
        i++;
      }
    } else if (src.startsWith('...', i)) {
      out.add(GqlToken(GqlTok.spread, '...', i, i + 3));
      i += 3;
    } else if (_punct.contains(src[i])) {
      out.add(GqlToken(GqlTok.punct, src[i], i, i + 1));
      i++;
    } else if (c == 34) {
      final start = i;
      if (src.startsWith('"""', i)) {
        var j = i + 3;
        final buf = StringBuffer();
        var closed = false;
        while (j < n) {
          if (src.startsWith(r'\"""', j)) {
            buf.write('"""');
            j += 4;
          } else if (src.startsWith('"""', j)) {
            closed = true;
            j += 3;
            break;
          } else {
            buf.write(src[j]);
            j++;
          }
        }
        if (!closed) return GqlLexed(out, openString: true);
        out.add(
          GqlToken(GqlTok.blockString, _dedent(buf.toString()), start, j),
        );
        i = j;
      } else {
        var j = i + 1;
        final buf = StringBuffer();
        var closed = false;
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
            closed = true;
            j++;
            break;
          } else {
            buf.write(src[j]);
            j++;
          }
        }
        if (!closed) return GqlLexed(out, openString: true);
        out.add(GqlToken(GqlTok.string, buf.toString(), start, j));
        i = j;
      }
    } else if (c == 36) {
      var j = i + 1;
      while (j < n && isPart(src.codeUnitAt(j))) {
        j++;
      }
      out.add(GqlToken(GqlTok.variable, src.substring(i, j), i, j));
      i = j;
    } else if (isStart(c)) {
      var j = i + 1;
      while (j < n && isPart(src.codeUnitAt(j))) {
        j++;
      }
      out.add(GqlToken(GqlTok.name, src.substring(i, j), i, j));
      i = j;
    } else if ((c >= 48 && c <= 57) || c == 45) {
      var j = i + 1;
      while (j < n && RegExp(r'[0-9.eE+\-]').hasMatch(src[j])) {
        j++;
      }
      out.add(GqlToken(GqlTok.number, src.substring(i, j), i, j));
      i = j;
    } else {
      i++;
    }
  }
  return GqlLexed(out);
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
