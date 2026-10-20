import 'lexer.dart';
import 'schema.dart';

class GqlSuggestion {
  const GqlSuggestion(this.label, this.detail, {this.insert});

  /// The name shown in the list.
  final String label;

  /// The type, or a short note.
  final String detail;

  /// Text to put in place of the typed prefix; defaults to [label].
  final String? insert;

  String get text => insert ?? label;
}

class GqlCompletion {
  const GqlCompletion(this.replaceFrom, this.items);

  /// Offset where the typed prefix starts. The caret is where it ends.
  final int replaceFrom;
  final List<GqlSuggestion> items;
}

bool _isWordChar(int c) =>
    (c >= 65 && c <= 90) ||
    (c >= 97 && c <= 122) ||
    (c >= 48 && c <= 57) ||
    c == 95;

/// Suggestions for the caret at [offset] in [query] (FR-GQL-002): field names
/// inside a selection set, argument names inside `( … )`. Returns null when
/// nothing sensible applies (inside a string, no schema match, a value
/// position).
GqlCompletion? graphqlComplete(GraphqlSchema schema, String query, int offset) {
  if (offset < 0 || offset > query.length) return null;
  final head = query.substring(0, offset);
  var prefixStart = offset;
  while (prefixStart > 0 && _isWordChar(head.codeUnitAt(prefixStart - 1))) {
    prefixStart--;
  }
  final prefix = head.substring(prefixStart);
  final before = head.substring(0, prefixStart);
  final lexed = lexGraphql(before);
  if (lexed.openString) return null;
  final scan = _scan(schema, lexed.tokens);
  return _suggest(schema, scan, prefix, prefixStart);
}

/// Where the caret sits in the query: the open selection sets and argument
/// lists, and the last token before it.
class _Scan {
  _Scan(this.stack, this.parens, this.prev);

  /// Each open `{` holds the type its fields belong to (null if unknown).
  final List<GqlType?> stack;

  /// Each open `(` holds the field whose arguments are being written.
  final List<GqlField?> parens;
  final GqlToken? prev;
}

_Scan _scan(GraphqlSchema schema, List<GqlToken> tokens) {
  final scanner = _Scanner(schema);
  for (final t in tokens) {
    scanner.feed(t);
  }
  return _Scan(scanner.stack, scanner.parens, scanner.prev);
}

/// Walks the tokens before the caret, tracking the open braces and parens.
class _Scanner {
  _Scanner(this.schema);

  final GraphqlSchema schema;
  final stack = <GqlType?>[];
  final parens = <GqlField?>[];
  GqlToken? prev;
  String? _opKeyword;
  String? _lastName; // last name seen at the current level, before `{` or `(`
  String? _inlineOn; // set after `... on` or `fragment X on`
  bool _sawOn = false;
  bool _fragmentDef = false;

  GqlType? get _top => stack.isEmpty ? null : stack.last;

  GqlField? _fieldNamed(String? name) =>
      _top?.fields.where((f) => f.name == name).firstOrNull;

  void feed(GqlToken t) {
    if (parens.isNotEmpty) {
      if (t.isPunct('(')) parens.add(null);
      if (t.isPunct(')')) parens.removeLast();
    } else if (t.kind == GqlTok.name) {
      _name(t.text);
    } else if (t.isPunct('(')) {
      parens.add(_fieldNamed(_lastName));
    } else if (t.isPunct('{')) {
      _openBrace();
    } else if (t.isPunct('}')) {
      if (stack.isNotEmpty) stack.removeLast();
      _lastName = null;
    }
    prev = t;
  }

  void _name(String text) {
    if (stack.isEmpty &&
        (text == 'query' || text == 'mutation' || text == 'subscription')) {
      _opKeyword = text;
      _fragmentDef = false;
    } else if (stack.isEmpty && text == 'fragment') {
      _fragmentDef = true;
    } else if (text == 'on' && (prev?.kind == GqlTok.spread || _fragmentDef)) {
      _sawOn = true;
    } else if (_sawOn) {
      _inlineOn = text;
      _sawOn = false;
    } else {
      _lastName = text;
    }
  }

  /// The type the selection set that opens now belongs to.
  GqlType? _nextType() {
    final on = _inlineOn;
    if (stack.isEmpty) {
      if (on != null) return schema.type(on);
      return schema.type(switch (_opKeyword) {
        'mutation' => schema.mutationType ?? '',
        'subscription' => schema.subscriptionType ?? '',
        _ => schema.queryType,
      });
    }
    if (on != null) return schema.type(on);
    if (prev?.kind == GqlTok.spread) return _top;
    final f = _fieldNamed(_lastName);
    return f == null ? null : schema.type(f.namedType);
  }

  void _openBrace() {
    stack.add(_nextType());
    _lastName = null;
    _inlineOn = null;
    _opKeyword = null;
    _fragmentDef = false;
  }
}

GqlCompletion? _suggest(
  GraphqlSchema schema,
  _Scan scan,
  String prefix,
  int prefixStart,
) {
  final parens = scan.parens;
  final stack = scan.stack;
  final prev = scan.prev;
  final lower = prefix.toLowerCase();
  bool matches(String name) =>
      prefix.isEmpty || name.toLowerCase().startsWith(lower);

  if (parens.isNotEmpty) {
    final field = parens.last;
    if (field == null || prev?.isPunct(':') == true) return null;
    final items = [
      for (final a in field.args)
        if (matches(a.name))
          GqlSuggestion(a.name, a.type, insert: '${a.name}: '),
    ];
    return items.isEmpty ? null : GqlCompletion(prefixStart, items);
  }

  final owner = stack.isEmpty ? null : stack.last;
  if (owner == null) return null;
  if (owner.kind != GqlKind.object && owner.kind != GqlKind.interface) {
    if (owner.kind == GqlKind.union) {
      return GqlCompletion(prefixStart, [
        const GqlSuggestion('__typename', 'String'),
        for (final p in owner.possibleTypes)
          if (matches('... on $p') || matches(p))
            GqlSuggestion('... on $p', 'fragment', insert: '... on $p {'),
      ]);
    }
    return null;
  }
  final items = [
    for (final f in owner.fields)
      if (matches(f.name))
        GqlSuggestion(
          f.name,
          f.type,
          insert: _needsSelection(schema, f) ? '${f.name} {' : f.name,
        ),
    if (matches('__typename')) const GqlSuggestion('__typename', 'String'),
  ];
  return items.isEmpty ? null : GqlCompletion(prefixStart, items);
}

bool _needsSelection(GraphqlSchema schema, GqlField f) {
  final t = schema.type(f.namedType);
  return t != null &&
      (t.kind == GqlKind.object ||
          t.kind == GqlKind.interface ||
          t.kind == GqlKind.union);
}
