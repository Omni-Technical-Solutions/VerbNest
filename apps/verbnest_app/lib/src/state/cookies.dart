/// A cookie from a `Set-Cookie` response header (read-only display).
class SetCookie {
  const SetCookie(this.name, this.value, this.attributes);

  final String name;
  final String value;

  /// Attribute names are lower-cased; flags such as `HttpOnly` map to ''.
  final Map<String, String> attributes;
}

SetCookie? parseSetCookie(String header) {
  final parts = header.split(';');
  final first = parts.first;
  final eq = first.indexOf('=');
  if (eq <= 0) return null;
  final attrs = <String, String>{};
  for (final p in parts.skip(1)) {
    final t = p.trim();
    if (t.isEmpty) continue;
    final i = t.indexOf('=');
    attrs[(i == -1 ? t : t.substring(0, i)).trim().toLowerCase()] = i == -1
        ? ''
        : t.substring(i + 1).trim();
  }
  return SetCookie(
    first.substring(0, eq).trim(),
    first.substring(eq + 1).trim(),
    attrs,
  );
}

/// Number of non-overlapping, case-insensitive occurrences of [query].
int countMatches(String text, String query) {
  if (query.isEmpty) return 0;
  final t = text.toLowerCase();
  final q = query.toLowerCase();
  var n = 0;
  for (var i = t.indexOf(q); i != -1; i = t.indexOf(q, i + q.length)) {
    n++;
  }
  return n;
}
