// Light-weight JavaScript highlighting and `pm.` completion for the script
// editor. It tokenises one line of text at a time without a full parser.

enum JsTokenKind { comment, string, number, keyword, api }

class JsToken {
  const JsToken(this.kind, this.start, this.end);

  final JsTokenKind kind;
  final int start;
  final int end;

  @override
  String toString() => '$kind[$start,$end)';
}

const _keywords = {
  'var', 'let', 'const', 'function', 'return', 'if', 'else', 'for', 'while', //
  'do', 'break', 'continue', 'switch', 'case', 'default', 'try', 'catch',
  'finally', 'throw', 'new', 'typeof', 'instanceof', 'in', 'of', 'async',
  'await', 'true', 'false', 'null', 'undefined', 'this',
};

bool _isIdStart(int c) =>
    (c >= 65 && c <= 90) || (c >= 97 && c <= 122) || c == 95 || c == 36;
bool _isDigit(int c) => c >= 48 && c <= 57;

/// Finds comments, strings, numbers, keywords and the `pm` / `console`
/// objects. Template literals are treated as strings up to the closing
/// backtick (or the end of the text while it is still being typed).
List<JsToken> tokenizeJs(String s) {
  final out = <JsToken>[];
  var i = 0;
  while (i < s.length) {
    final c = s.codeUnitAt(i);
    final next = i + 1 < s.length ? s.codeUnitAt(i + 1) : -1;
    if (c == 47 && next == 47) {
      i = _add(out, JsTokenKind.comment, i, _lineEnd(s, i));
    } else if (c == 47 && next == 42) {
      final j = s.indexOf('*/', i + 2);
      i = _add(out, JsTokenKind.comment, i, j == -1 ? s.length : j + 2);
    } else if (c == 34 || c == 39 || c == 96) {
      i = _add(out, JsTokenKind.string, i, _stringEnd(s, i, c));
    } else if (_isDigit(c)) {
      i = _add(out, JsTokenKind.number, i, _numberEnd(s, i));
    } else if (_isIdStart(c)) {
      i = _word(s, i, out);
    } else {
      i++;
    }
  }
  return out;
}

int _add(List<JsToken> out, JsTokenKind kind, int start, int end) {
  out.add(JsToken(kind, start, end));
  return end;
}

int _lineEnd(String s, int i) {
  final j = s.indexOf('\n', i);
  return j == -1 ? s.length : j;
}

/// The end of the string that opens at [i] with quote [q]. A quote or
/// backslash ends or escapes; only a template literal may span lines.
int _stringEnd(String s, int i, int q) {
  var j = i + 1;
  while (j < s.length && s.codeUnitAt(j) != q) {
    if (s.codeUnitAt(j) == 92) j++;
    if (q != 96 && j < s.length && s.codeUnitAt(j) == 10) break;
    j++;
  }
  return j < s.length && s.codeUnitAt(j) == q ? j + 1 : j.clamp(0, s.length);
}

int _numberEnd(String s, int i) {
  var j = i + 1;
  while (j < s.length) {
    final c = s.codeUnitAt(j);
    if (!_isDigit(c) && c != 46 && !_isIdStart(c)) break;
    j++;
  }
  return j;
}

/// Adds the keyword or API token for the word at [i] (if it is one) and
/// returns where the word ends.
int _word(String s, int i, List<JsToken> out) {
  var j = i + 1;
  while (j < s.length) {
    final c = s.codeUnitAt(j);
    if (!_isIdStart(c) && !_isDigit(c)) break;
    j++;
  }
  final word = s.substring(i, j);
  final afterDot = i > 0 && s.codeUnitAt(i - 1) == 46;
  if (!afterDot && (word == 'pm' || word == 'console')) {
    out.add(JsToken(JsTokenKind.api, i, j));
  } else if (!afterDot && _keywords.contains(word)) {
    out.add(JsToken(JsTokenKind.keyword, i, j));
  }
  return j;
}

/// The members VerbNest scripts can use, for completion.
const scriptApi = [
  'pm.variables.get',
  'pm.variables.set',
  'pm.variables.has',
  'pm.environment.get',
  'pm.environment.set',
  'pm.environment.unset',
  'pm.collectionVariables.get',
  'pm.collectionVariables.set',
  'pm.globals.get',
  'pm.globals.set',
  'pm.globals.unset',
  'pm.request.url',
  'pm.request.method',
  'pm.request.headers',
  'pm.request.body',
  'pm.response.code',
  'pm.response.status',
  'pm.response.headers',
  'pm.response.text',
  'pm.response.json',
  'pm.response.responseTime',
  'pm.response.to.have.status',
  'pm.response.to.have.header',
  'pm.test',
  'pm.expect',
  'pm.execution.setNextRequest',
  'console.log',
  'console.warn',
  'console.error',
  'console.info',
];

/// The `pm.xxx` / `console.xx` word that ends at [caret], or null.
String? scriptPrefix(String text, int caret) {
  if (caret < 0 || caret > text.length) return null;
  var i = caret;
  while (i > 0) {
    final c = text.codeUnitAt(i - 1);
    if (_isIdStart(c) || _isDigit(c) || c == 46) {
      i--;
    } else {
      break;
    }
  }
  final word = text.substring(i, caret);
  if (word.isEmpty) return null;
  return word;
}

/// Up to [max] API names that start with [prefix]; none when it is already
/// an exact and only match.
List<String> scriptCompletions(String prefix, {int max = 8}) {
  if (prefix.length < 2) return const [];
  final hits = [
    for (final a in scriptApi)
      if (a.startsWith(prefix) && a != prefix) a,
  ];
  return hits.take(max).toList();
}

({String text, int caret}) applyScriptCompletion(
  String text,
  int caret,
  String name,
) {
  final prefix = scriptPrefix(text, caret) ?? '';
  final start = caret - prefix.length;
  return (
    text: text.substring(0, start) + name + text.substring(caret),
    caret: start + name.length,
  );
}
