/// A small JSONPath: `$`, `.name`, `['name']`, `[0]`, `[-1]`, `[*]`, `.*` and
/// `..name` (recursive). Filters and slices are not supported and throw a
/// [FormatException], so a typo never silently matches nothing.
List<Object?> jsonPath(Object? root, String path) {
  final steps = _parse(path.trim());
  var nodes = <Object?>[root];
  for (final step in steps) {
    final next = <Object?>[];
    for (final n in nodes) {
      step.apply(n, next);
    }
    nodes = next;
  }
  return nodes;
}

abstract class _Step {
  void apply(Object? node, List<Object?> out);
}

class _Key implements _Step {
  _Key(this.key);
  final String key;

  @override
  void apply(Object? node, List<Object?> out) {
    if (node is Map && node.containsKey(key)) out.add(node[key]);
  }
}

class _Index implements _Step {
  _Index(this.index);
  final int index;

  @override
  void apply(Object? node, List<Object?> out) {
    if (node is! List) return;
    final i = index < 0 ? node.length + index : index;
    if (i >= 0 && i < node.length) out.add(node[i]);
  }
}

class _Wildcard implements _Step {
  @override
  void apply(Object? node, List<Object?> out) {
    if (node is List) out.addAll(node);
    if (node is Map) out.addAll(node.values);
  }
}

class _Recursive implements _Step {
  _Recursive(this.key);

  /// Null matches every descendant.
  final String? key;

  @override
  void apply(Object? node, List<Object?> out) {
    void walk(Object? n) {
      if (n is Map) {
        for (final e in n.entries) {
          if (key == null || e.key == key) out.add(e.value);
          walk(e.value);
        }
      } else if (n is List) {
        for (final v in n) {
          if (key == null) out.add(v);
          walk(v);
        }
      }
    }

    walk(node);
  }
}

List<_Step> _parse(String path) {
  if (!path.startsWith(r'$')) {
    throw FormatException('A JSONPath starts with \$', path);
  }
  final steps = <_Step>[];
  var i = 1;
  while (i < path.length) {
    final c = path[i];
    if (c == '.') {
      final recursive = i + 1 < path.length && path[i + 1] == '.';
      i += recursive ? 2 : 1;
      if (i < path.length && path[i] == '[') {
        // `..[...]` is not needed; fall through to bracket parsing.
        if (recursive) throw FormatException('Unsupported JSONPath', path);
        continue;
      }
      final start = i;
      while (i < path.length && path[i] != '.' && path[i] != '[') {
        i++;
      }
      final name = path.substring(start, i);
      if (name.isEmpty) throw FormatException('Empty name in JSONPath', path);
      if (recursive) {
        steps.add(_Recursive(name == '*' ? null : name));
      } else {
        steps.add(name == '*' ? _Wildcard() : _Key(name));
      }
    } else if (c == '[') {
      final quoted = _quotedKey(path, i);
      if (quoted != null) {
        steps.add(_Key(quoted.key));
        i = quoted.end;
        continue;
      }
      final end = path.indexOf(']', i);
      if (end == -1) throw FormatException('Missing ] in JSONPath', path);
      final inner = path.substring(i + 1, end).trim();
      i = end + 1;
      if (inner == '*') {
        steps.add(_Wildcard());
      } else if (inner.startsWith("'") || inner.startsWith('"')) {
        throw FormatException('Bad JSONPath key', path);
      } else if (int.tryParse(inner) != null) {
        steps.add(_Index(int.parse(inner)));
      } else {
        throw FormatException('Unsupported JSONPath selector [$inner]', path);
      }
    } else {
      throw FormatException('Unexpected "$c" in JSONPath', path);
    }
  }
  return steps;
}

/// A bracketed, quoted key at [i] (`['a b']` or `["a"]`), where a backslash
/// escapes the next character, so a key may hold quotes, brackets and
/// backslashes. Null when the bracket does not hold a quoted key; throws when
/// it does but is not closed.
({String key, int end})? _quotedKey(String path, int i) {
  var j = i + 1;
  while (j < path.length && path[j] == ' ') {
    j++;
  }
  if (j >= path.length || (path[j] != "'" && path[j] != '"')) return null;
  final quote = path[j++];
  final key = StringBuffer();
  var closed = false;
  while (j < path.length) {
    final ch = path[j];
    if (ch == r'\') {
      if (j + 1 >= path.length) break;
      key.write(path[j + 1]);
      j += 2;
    } else if (ch == quote) {
      closed = true;
      j++;
      break;
    } else {
      key.write(ch);
      j++;
    }
  }
  if (!closed) throw FormatException('Bad JSONPath key', path);
  while (j < path.length && path[j] == ' ') {
    j++;
  }
  if (j >= path.length || path[j] != ']') {
    throw FormatException('Missing ] in JSONPath', path);
  }
  return (key: key.toString(), end: j + 1);
}
