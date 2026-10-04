/// Splits a shell command line into words the way a POSIX shell would for
/// the subset cURL commands use: single and double quotes, `$'...'`,
/// backslash escapes and line continuations. Nothing is expanded.
List<String> shellSplit(String input) {
  final out = <String>[];
  final cur = StringBuffer();
  var inWord = false;
  var i = 0;

  void flush() {
    if (inWord) out.add(cur.toString());
    cur.clear();
    inWord = false;
  }

  while (i < input.length) {
    final c = input[i];
    if (c == ' ' || c == '\t' || c == '\n' || c == '\r') {
      flush();
      i++;
    } else if (c == '\\') {
      if (i + 1 >= input.length) {
        i++;
      } else if (input[i + 1] == '\n') {
        i += 2; // line continuation
      } else if (input[i + 1] == '\r' &&
          i + 2 < input.length &&
          input[i + 2] == '\n') {
        i += 3;
      } else {
        cur.write(input[i + 1]);
        inWord = true;
        i += 2;
      }
    } else if (c == "'") {
      final end = input.indexOf("'", i + 1);
      if (end == -1) throw const FormatException('Unterminated single quote');
      cur.write(input.substring(i + 1, end));
      inWord = true;
      i = end + 1;
    } else if (c == r'$' && i + 1 < input.length && input[i + 1] == "'") {
      i = _ansiC(input, i + 2, cur);
      inWord = true;
    } else if (c == '"') {
      i = _doubleQuoted(input, i + 1, cur);
      inWord = true;
    } else {
      cur.write(c);
      inWord = true;
      i++;
    }
  }
  flush();
  return out;
}

int _doubleQuoted(String s, int i, StringBuffer out) {
  while (i < s.length) {
    final c = s[i];
    if (c == '"') return i + 1;
    if (c == '\\' && i + 1 < s.length) {
      final n = s[i + 1];
      if (n == '"' || n == '\\' || n == r'$' || n == '`') {
        out.write(n);
        i += 2;
        continue;
      }
      if (n == '\n') {
        i += 2;
        continue;
      }
    }
    out.write(c);
    i++;
  }
  throw const FormatException('Unterminated double quote');
}

int _ansiC(String s, int i, StringBuffer out) {
  while (i < s.length) {
    final c = s[i];
    if (c == "'") return i + 1;
    if (c == '\\' && i + 1 < s.length) {
      final n = s[i + 1];
      switch (n) {
        case 'n':
          out.write('\n');
        case 't':
          out.write('\t');
        case 'r':
          out.write('\r');
        case '\\':
        case "'":
        case '"':
          out.write(n);
        case 'x':
          final hex = s.substring(i + 2, (i + 4).clamp(0, s.length));
          final code = int.tryParse(hex, radix: 16);
          if (code != null) {
            out.writeCharCode(code);
            i += 2 + hex.length;
            continue;
          }
          out.write(r'\x');
        case 'u':
          final hex = s.substring(i + 2, (i + 6).clamp(0, s.length));
          final code = int.tryParse(hex, radix: 16);
          if (code != null) {
            out.writeCharCode(code);
            i += 2 + hex.length;
            continue;
          }
          out.write(r'\u');
        default:
          out.write('\\$n');
      }
      i += 2;
      continue;
    }
    out.write(c);
    i++;
  }
  throw const FormatException(r"Unterminated $'...' string");
}
