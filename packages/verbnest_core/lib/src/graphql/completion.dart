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

/// Suggestions for the caret at [offset] in [query] (FR-GQL-002): field names
/// inside a selection set, argument names inside `( … )`. Returns null when
/// nothing sensible applies (inside a string, no schema match, a value
/// position).
GqlCompletion? graphqlComplete(GraphqlSchema schema, String query, int offset) {
  if (offset < 0 || offset > query.length) return null;
  final head = query.substring(0, offset);
  var prefixStart = offset;
  while (prefixStart > 0 &&
      RegExp(r'[A-Za-z0-9_]').hasMatch(head[prefixStart - 1])) {
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
  final stack = <GqlType?>[];
  final parens = <GqlField?>[];
  String? opKeyword;
  String? lastName; // last name seen at the current level, before `{` or `(`
  String? inlineOn; // set after `... on` or `fragment X on`
  var sawOn = false;
  GqlToken? prev;
  var fragmentDef = false;

  GqlType? top() => stack.isEmpty ? null : stack.last;

  for (final t in tokens) {
    if (parens.isNotEmpty) {
      if (t.isPunct('(')) parens.add(null);
      if (t.isPunct(')')) parens.removeLast();
      prev = t;
      continue;
    }
    if (t.kind == GqlTok.name) {
      if (stack.isEmpty &&
          (t.text == 'query' ||
              t.text == 'mutation' ||
              t.text == 'subscription')) {
        opKeyword = t.text;
        fragmentDef = false;
      } else if (stack.isEmpty && t.text == 'fragment') {
        fragmentDef = true;
      } else if (t.text == 'on' &&
          (prev?.kind == GqlTok.spread || fragmentDef)) {
        sawOn = true;
      } else if (sawOn) {
        inlineOn = t.text;
        sawOn = false;
      } else {
        lastName = t.text;
      }
    } else if (t.isPunct('(')) {
      final field = top()?.fields.where((f) => f.name == lastName).firstOrNull;
      parens.add(field);
    } else if (t.isPunct('{')) {
      GqlType? next;
      if (stack.isEmpty) {
        if (inlineOn != null) {
          next = schema.type(inlineOn);
        } else {
          next = schema.type(switch (opKeyword) {
            'mutation' => schema.mutationType ?? '',
            'subscription' => schema.subscriptionType ?? '',
            _ => schema.queryType,
          });
        }
      } else if (inlineOn != null) {
        next = schema.type(inlineOn);
      } else if (prev?.kind == GqlTok.spread) {
        next = top();
      } else {
        final f = top()?.fields.where((f) => f.name == lastName).firstOrNull;
        next = f == null ? null : schema.type(f.namedType);
      }
      stack.add(next);
      lastName = null;
      inlineOn = null;
      opKeyword = null;
      fragmentDef = false;
    } else if (t.isPunct('}')) {
      if (stack.isNotEmpty) stack.removeLast();
      lastName = null;
    }
    prev = t;
  }
  return _Scan(stack, parens, prev);
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
