/// Matches [pattern] against [text], or returns null when the pattern is
/// invalid or looks likely to backtrack without end.
///
/// Dart's RegExp cannot be interrupted, and patterns come from imported
/// collections and schemas. This refuses long patterns and nested
/// quantifiers such as `(a+)+`, and only looks at the first 100,000
/// characters of [text]. It reduces the risk and does not remove it.
bool? safeRegexMatch(String pattern, String text) {
  if (pattern.length > 500 || _nestedQuantifier.hasMatch(pattern)) return null;
  try {
    final input = text.length > 100000 ? text.substring(0, 100000) : text;
    return RegExp(pattern).hasMatch(input);
  } on FormatException {
    return null;
  }
}

final _nestedQuantifier = RegExp(
  r'\((?:[^()\\]|\\.)*[+*}](?:[^()\\]|\\.)*\)[+*{]',
);
