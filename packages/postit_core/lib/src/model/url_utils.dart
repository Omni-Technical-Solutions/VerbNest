import 'key_value.dart';

/// URL <-> params helpers (FR-HTTP-003/004). Everything works on the raw text
/// the user typed: nothing is decoded or re-encoded (constitution V.2), and
/// `{{variables}}` pass through untouched.
class UrlText {
  UrlText._();

  static final _pathVar = RegExp(r'/:([A-Za-z_][A-Za-z0-9_\-]*)');

  /// `(base, query, fragment)`; query and fragment are null when absent.
  static (String, String?, String?) split(String url) {
    var rest = url;
    String? fragment;
    final hash = rest.indexOf('#');
    if (hash != -1) {
      fragment = rest.substring(hash + 1);
      rest = rest.substring(0, hash);
    }
    String? query;
    final q = rest.indexOf('?');
    if (q != -1) {
      query = rest.substring(q + 1);
      rest = rest.substring(0, q);
    }
    return (rest, query, fragment);
  }

  /// Query parameters in order, duplicates and empty values kept.
  static List<KeyValue> params(String url) {
    final query = split(url).$2;
    if (query == null || query.isEmpty) return const [];
    return [
      for (final pair in query.split('&'))
        if (pair.isNotEmpty) _pair(pair),
    ];
  }

  static KeyValue _pair(String pair) {
    final eq = pair.indexOf('=');
    return eq == -1
        ? KeyValue(key: pair)
        : KeyValue(key: pair.substring(0, eq), value: pair.substring(eq + 1));
  }

  /// Rebuilds [url] so its query holds exactly the enabled [params].
  static String withParams(String url, List<KeyValue> params) {
    final (base, _, fragment) = split(url);
    // The table cannot tell `?a` from `?a=`, so rows are always `key=value`.
    // Callers should only rewrite the URL when the table itself was edited.
    final query = [
      for (final p in params)
        if (p.enabled) '${p.key}=${p.value}',
    ].join('&');
    return '$base${query.isEmpty ? '' : '?$query'}'
        '${fragment == null ? '' : '#$fragment'}';
  }

  /// Names of `:name` segments in the path part of [url], in order, unique.
  static List<String> pathVariables(String url) {
    final base = split(url).$1;
    final afterScheme = base.contains('://')
        ? base.substring(base.indexOf('://') + 3)
        : base;
    final slash = afterScheme.indexOf('/');
    final path = slash == -1 ? '' : afterScheme.substring(slash);
    final names = <String>{};
    for (final m in _pathVar.allMatches(path)) {
      names.add(m.group(1)!);
    }
    return names.toList();
  }

  /// Replaces `/:name` segments using [values]; unknown names stay as typed.
  static String applyPathVariables(String url, Map<String, String> values) {
    final (base, query, fragment) = split(url);
    final scheme = base.contains('://') ? base.indexOf('://') + 3 : 0;
    final slash = base.indexOf('/', scheme);
    if (slash == -1) return url;
    final path = base.substring(slash).replaceAllMapped(_pathVar, (m) {
      final v = values[m.group(1)!];
      return v == null ? m.group(0)! : '/$v';
    });
    return '${base.substring(0, slash)}$path'
        '${query == null ? '' : '?$query'}'
        '${fragment == null ? '' : '#$fragment'}';
  }
}
