import 'lexer.dart';

/// The standard introspection query. It asks for everything the explorer,
/// completion and SDL export need.
const graphqlIntrospectionQuery = r'''
query IntrospectionQuery {
  __schema {
    queryType { name }
    mutationType { name }
    subscriptionType { name }
    types {
      kind name description
      fields(includeDeprecated: true) {
        name description isDeprecated deprecationReason
        args { name description defaultValue type { ...TypeRef } }
        type { ...TypeRef }
      }
      inputFields { name description defaultValue type { ...TypeRef } }
      interfaces { ...TypeRef }
      enumValues(includeDeprecated: true) { name description isDeprecated deprecationReason }
      possibleTypes { ...TypeRef }
    }
  }
}
fragment TypeRef on __Type {
  kind name
  ofType { kind name ofType { kind name ofType { kind name ofType { kind name ofType { kind name ofType { kind name ofType { kind name } } } } } } }
}
''';

enum GqlKind { scalar, object, interface, union, enumeration, inputObject }

/// An argument of a field, or a field of an input object.
class GqlArg {
  const GqlArg(
    this.name,
    this.type, {
    this.defaultValue,
    this.description = '',
  });

  final String name;

  /// Type as written in SDL, such as `[User!]!`.
  final String type;
  final String? defaultValue;
  final String description;

  String get namedType => namedTypeOf(type);
}

class GqlField {
  const GqlField(
    this.name,
    this.type, {
    this.args = const [],
    this.description = '',
    this.deprecated,
  });

  final String name;
  final String type;
  final List<GqlArg> args;
  final String description;

  /// The deprecation reason, or an empty string when none was given; null if
  /// not deprecated.
  final String? deprecated;

  String get namedType => namedTypeOf(type);
}

class GqlEnumValue {
  const GqlEnumValue(this.name, {this.description = '', this.deprecated});

  final String name;
  final String description;
  final String? deprecated;
}

class GqlType {
  GqlType(this.name, this.kind, {this.description = ''});

  final String name;
  final GqlKind kind;
  String description;
  final List<GqlField> fields = [];
  final List<GqlArg> inputFields = [];
  final List<GqlEnumValue> enumValues = [];
  final List<String> possibleTypes = [];
  final List<String> interfaces = [];

  bool get isBuiltIn =>
      name.startsWith('__') ||
      (kind == GqlKind.scalar && builtInScalars.contains(name));
}

const builtInScalars = {'Int', 'Float', 'String', 'Boolean', 'ID'};

/// `[User!]!` becomes `User`.
String namedTypeOf(String type) => type.replaceAll(RegExp(r'[\[\]!\s]'), '');

/// A GraphQL schema read from an introspection result or from SDL
/// (FR-GQL-002).
class GraphqlSchema {
  GraphqlSchema({
    required this.types,
    this.queryType = 'Query',
    this.mutationType,
    this.subscriptionType,
  });

  final Map<String, GqlType> types;
  final String queryType;
  final String? mutationType;
  final String? subscriptionType;

  GqlType? type(String name) => types[name];

  /// Types worth showing in an explorer: everything except `__` types and the
  /// five built-in scalars.
  List<GqlType> get userTypes => [
    for (final t in types.values)
      if (!t.isBuiltIn) t,
  ];

  /// Accepts the response body of the introspection query (with or without the
  /// `data` wrapper). Throws [FormatException] when it is not one.
  factory GraphqlSchema.fromIntrospection(Object? json) {
    Object? root = json;
    if (root is Map && root['errors'] is List && root['data'] == null) {
      final first = (root['errors'] as List).firstOrNull;
      final msg = first is Map ? first['message'] : null;
      throw FormatException(
        'The server returned an error: ${msg ?? 'unknown'}',
      );
    }
    if (root is Map && root['data'] is Map) root = root['data'];
    final schema = root is Map ? root['__schema'] : null;
    if (schema is! Map) {
      throw const FormatException('Not a GraphQL introspection result');
    }
    final types = <String, GqlType>{};
    for (final raw in (schema['types'] as List? ?? const [])) {
      if (raw is! Map) continue;
      final name = raw['name'] as String?;
      final kind = _kindOf(raw['kind'] as String?);
      if (name == null || kind == null) continue;
      final t = GqlType(
        name,
        kind,
        description: raw['description'] as String? ?? '',
      );
      for (final f in (raw['fields'] as List? ?? const [])) {
        if (f is! Map) continue;
        t.fields.add(
          GqlField(
            f['name'] as String? ?? '',
            _typeText(f['type']),
            args: _args(f['args']),
            description: f['description'] as String? ?? '',
            deprecated: f['isDeprecated'] == true
                ? (f['deprecationReason'] as String? ?? '')
                : null,
          ),
        );
      }
      t.inputFields.addAll(_args(raw['inputFields']));
      for (final v in (raw['enumValues'] as List? ?? const [])) {
        if (v is! Map) continue;
        t.enumValues.add(
          GqlEnumValue(
            v['name'] as String? ?? '',
            description: v['description'] as String? ?? '',
            deprecated: v['isDeprecated'] == true
                ? (v['deprecationReason'] as String? ?? '')
                : null,
          ),
        );
      }
      for (final p in (raw['possibleTypes'] as List? ?? const [])) {
        if (p is Map && p['name'] is String) {
          t.possibleTypes.add(p['name'] as String);
        }
      }
      for (final p in (raw['interfaces'] as List? ?? const [])) {
        if (p is Map && p['name'] is String) {
          t.interfaces.add(p['name'] as String);
        }
      }
      types[name] = t;
    }
    String? root0(String key) => (schema[key] as Map?)?['name'] as String?;
    return GraphqlSchema(
      types: types,
      queryType: root0('queryType') ?? 'Query',
      mutationType: root0('mutationType'),
      subscriptionType: root0('subscriptionType'),
    );
  }

  static GqlKind? _kindOf(String? kind) => switch (kind) {
    'SCALAR' => GqlKind.scalar,
    'OBJECT' => GqlKind.object,
    'INTERFACE' => GqlKind.interface,
    'UNION' => GqlKind.union,
    'ENUM' => GqlKind.enumeration,
    'INPUT_OBJECT' => GqlKind.inputObject,
    _ => null,
  };

  /// Deepest list/non-null wrapping accepted in a type reference.
  static const _maxTypeDepth = 64;

  static String _typeText(Object? ref, [int depth = 0]) {
    if (ref is! Map) return 'String';
    if (depth > _maxTypeDepth) {
      throw const FormatException('Type reference is nested too deeply');
    }
    return switch (ref['kind']) {
      'NON_NULL' => '${_typeText(ref['ofType'], depth + 1)}!',
      'LIST' => '[${_typeText(ref['ofType'], depth + 1)}]',
      _ => ref['name'] as String? ?? 'String',
    };
  }

  static List<GqlArg> _args(Object? raw) => [
    for (final a in (raw as List? ?? const []))
      if (a is Map)
        GqlArg(
          a['name'] as String? ?? '',
          _typeText(a['type']),
          defaultValue: a['defaultValue'] as String?,
          description: a['description'] as String? ?? '',
        ),
  ];

  /// Reads schema definition language. Directive definitions are skipped;
  /// directives on definitions are ignored except `@deprecated`. `extend`
  /// blocks are merged into the type they extend.
  factory GraphqlSchema.fromSdl(String sdl) => _SdlParser(sdl).parse();

  /// Writes the schema as SDL, readable and stable.
  String toSdl() {
    final b = StringBuffer();
    final defaults =
        queryType == 'Query' &&
        (mutationType == null || mutationType == 'Mutation') &&
        (subscriptionType == null || subscriptionType == 'Subscription');
    if (!defaults) {
      b.writeln('schema {');
      b.writeln('  query: $queryType');
      if (mutationType != null) b.writeln('  mutation: $mutationType');
      if (subscriptionType != null) {
        b.writeln('  subscription: $subscriptionType');
      }
      b.writeln('}\n');
    }
    for (final t in userTypes) {
      _writeDescription(b, t.description, '');
      switch (t.kind) {
        case GqlKind.scalar:
          b.writeln('scalar ${t.name}');
        case GqlKind.object || GqlKind.interface:
          final kw = t.kind == GqlKind.object ? 'type' : 'interface';
          final impl = t.interfaces.isEmpty
              ? ''
              : ' implements ${t.interfaces.join(' & ')}';
          b.writeln('$kw ${t.name}$impl {');
          for (final f in t.fields) {
            _writeDescription(b, f.description, '  ');
            b.write('  ${f.name}');
            if (f.args.isNotEmpty) {
              b.write('(${f.args.map(_argText).join(', ')})');
            }
            b.write(': ${f.type}');
            if (f.deprecated != null) b.write(_deprecatedText(f.deprecated!));
            b.writeln();
          }
          b.writeln('}');
        case GqlKind.inputObject:
          b.writeln('input ${t.name} {');
          for (final f in t.inputFields) {
            _writeDescription(b, f.description, '  ');
            b.writeln('  ${_argText(f)}');
          }
          b.writeln('}');
        case GqlKind.enumeration:
          b.writeln('enum ${t.name} {');
          for (final v in t.enumValues) {
            _writeDescription(b, v.description, '  ');
            b.writeln(
              '  ${v.name}${v.deprecated == null ? '' : _deprecatedText(v.deprecated!)}',
            );
          }
          b.writeln('}');
        case GqlKind.union:
          b.writeln('union ${t.name} = ${t.possibleTypes.join(' | ')}');
      }
      b.writeln();
    }
    return '${b.toString().trimRight()}\n';
  }

  static String _argText(GqlArg a) =>
      '${a.name}: ${a.type}${a.defaultValue == null ? '' : ' = ${a.defaultValue}'}';

  static String _deprecatedText(String reason) => reason.isEmpty
      ? ' @deprecated'
      : ' @deprecated(reason: "${reason.replaceAll('\\', r'\\').replaceAll('"', r'\"')}")';

  static void _writeDescription(StringBuffer b, String d, String indent) {
    if (d.isEmpty) return;
    final safe = d.replaceAll('"""', r'\"""');
    if (!safe.contains('\n')) {
      b.writeln('$indent"""$safe"""');
    } else {
      b.writeln('$indent"""');
      for (final l in safe.split('\n')) {
        b.writeln('$indent$l');
      }
      b.writeln('$indent"""');
    }
  }
}

class _SdlParser {
  _SdlParser(this.src) : tokens = lexGraphql(src).tokens;

  final String src;
  final List<GqlToken> tokens;
  int p = 0;
  final types = <String, GqlType>{};
  String query = 'Query';
  String? mutation;
  String? subscription;

  GqlToken? get cur => p < tokens.length ? tokens[p] : null;

  FormatException _fail(String msg) {
    final t = cur;
    final line = t == null
        ? null
        : '\n'.allMatches(src.substring(0, t.start)).length + 1;
    return FormatException(line == null ? msg : '$msg (line $line)');
  }

  GqlToken _next() {
    final t = cur;
    if (t == null) throw _fail('Unexpected end of schema');
    p++;
    return t;
  }

  void _punct(String s) {
    if (cur?.isPunct(s) != true) throw _fail('Expected "$s"');
    p++;
  }

  bool _eatPunct(String s) {
    if (cur?.isPunct(s) == true) {
      p++;
      return true;
    }
    return false;
  }

  String _name() {
    final t = _next();
    if (t.kind != GqlTok.name) {
      p--;
      throw _fail('Expected a name');
    }
    return t.text;
  }

  String _description() {
    final t = cur;
    if (t != null &&
        (t.kind == GqlTok.string || t.kind == GqlTok.blockString)) {
      p++;
      return t.text;
    }
    return '';
  }

  GraphqlSchema parse() {
    for (final s in builtInScalars) {
      types[s] = GqlType(s, GqlKind.scalar);
    }
    while (cur != null) {
      _definition();
    }
    final schema = GraphqlSchema(
      types: types,
      queryType: query,
      mutationType:
          mutation ?? (types.containsKey('Mutation') ? 'Mutation' : null),
      subscriptionType:
          subscription ??
          (types.containsKey('Subscription') ? 'Subscription' : null),
    );
    if (types.length == builtInScalars.length) {
      throw const FormatException('No types found in the schema');
    }
    return schema;
  }

  void _definition() {
    final desc = _description();
    var kw = _name();
    var extend = false;
    if (kw == 'extend') {
      extend = true;
      kw = _name();
    }
    switch (kw) {
      case 'schema':
        _schemaDefinition();
      case 'scalar':
        final name = _name();
        _directives();
        _declare(name, GqlKind.scalar, desc, extend);
      case 'type' || 'interface':
        _objectDefinition(kw, desc, extend);
      case 'input':
        _inputDefinition(desc, extend);
      case 'enum':
        _enumDefinition(desc, extend);
      case 'union':
        _unionDefinition(desc, extend);
      case 'directive':
        _directiveDefinition();
      default:
        p--;
        throw _fail('Unexpected "$kw"');
    }
  }

  /// `schema { query: Q mutation: M subscription: S }`
  void _schemaDefinition() {
    _directives();
    _punct('{');
    while (!_eatPunct('}')) {
      final op = _name();
      _punct(':');
      final t = _name();
      switch (op) {
        case 'query':
          query = t;
        case 'mutation':
          mutation = t;
        case 'subscription':
          subscription = t;
      }
    }
  }

  /// `type` or `interface`, with its `implements` list and fields.
  void _objectDefinition(String kw, String desc, bool extend) {
    final name = _name();
    final t = _declare(
      name,
      kw == 'type' ? GqlKind.object : GqlKind.interface,
      desc,
      extend,
    );
    if (cur?.isName('implements') == true) {
      p++;
      _eatPunct('&');
      t.interfaces.add(_name());
      while (_eatPunct('&') ||
          (cur?.kind == GqlTok.name &&
              !_definitionKeywords.contains(cur?.text))) {
        t.interfaces.add(_name());
      }
    }
    _directives();
    if (_eatPunct('{')) {
      while (!_eatPunct('}')) {
        t.fields.add(_field());
      }
    }
  }

  void _inputDefinition(String desc, bool extend) {
    final name = _name();
    final t = _declare(name, GqlKind.inputObject, desc, extend);
    _directives();
    if (_eatPunct('{')) {
      while (!_eatPunct('}')) {
        t.inputFields.add(_inputValue());
      }
    }
  }

  void _enumDefinition(String desc, bool extend) {
    final name = _name();
    final t = _declare(name, GqlKind.enumeration, desc, extend);
    _directives();
    if (_eatPunct('{')) {
      while (!_eatPunct('}')) {
        final d = _description();
        final v = _name();
        final dep = _directives();
        t.enumValues.add(GqlEnumValue(v, description: d, deprecated: dep));
      }
    }
  }

  void _unionDefinition(String desc, bool extend) {
    final name = _name();
    final t = _declare(name, GqlKind.union, desc, extend);
    _directives();
    if (_eatPunct('=')) {
      _eatPunct('|');
      t.possibleTypes.add(_name());
      while (_eatPunct('|')) {
        t.possibleTypes.add(_name());
      }
    }
  }

  /// `directive @name(args) repeatable on A | B`; read and dropped.
  void _directiveDefinition() {
    _punct('@');
    _name();
    if (cur?.isPunct('(') == true) _skipBalanced('(', ')');
    if (cur?.isName('repeatable') == true) p++;
    if (cur?.isName('on') == true) {
      p++;
      _eatPunct('|');
      _name();
      while (_eatPunct('|')) {
        _name();
      }
    }
  }

  static const _definitionKeywords = {
    'schema', 'scalar', 'type', 'interface', 'union', 'enum', 'input', //
    'directive', 'extend',
  };

  GqlType _declare(String name, GqlKind kind, String desc, bool extend) {
    final existing = types[name];
    if (existing != null && (extend || builtInScalars.contains(name))) {
      if (desc.isNotEmpty) existing.description = desc;
      return existing;
    }
    return types[name] = GqlType(name, kind, description: desc);
  }

  GqlField _field() {
    final desc = _description();
    final name = _name();
    var args = <GqlArg>[];
    if (_eatPunct('(')) {
      while (!_eatPunct(')')) {
        args.add(_inputValue());
      }
    }
    _punct(':');
    final type = _typeRef();
    final dep = _directives();
    return GqlField(name, type, args: args, description: desc, deprecated: dep);
  }

  GqlArg _inputValue() {
    final desc = _description();
    final name = _name();
    _punct(':');
    final type = _typeRef();
    String? def;
    if (_eatPunct('=')) def = _valueText();
    _directives();
    return GqlArg(name, type, defaultValue: def, description: desc);
  }

  String _typeRef([int depth = 0]) {
    if (depth > GraphqlSchema._maxTypeDepth) {
      throw const FormatException('Type reference is nested too deeply');
    }
    String base;
    if (_eatPunct('[')) {
      base = '[${_typeRef(depth + 1)}]';
      _punct(']');
    } else {
      base = _name();
    }
    return _eatPunct('!') ? '$base!' : base;
  }

  /// Source text of one value (scalar, list or object).
  String _valueText() {
    final first = cur;
    if (first == null) throw _fail('Expected a value');
    if (first.isPunct('[')) {
      final start = first.start;
      _skipBalanced('[', ']');
      return src.substring(start, tokens[p - 1].end);
    }
    if (first.isPunct('{')) {
      final start = first.start;
      _skipBalanced('{', '}');
      return src.substring(start, tokens[p - 1].end);
    }
    p++;
    return src.substring(first.start, first.end);
  }

  void _skipBalanced(String open, String close) {
    var depth = 0;
    while (cur != null) {
      final t = _next();
      if (t.isPunct(open)) depth++;
      if (t.isPunct(close) && --depth == 0) return;
    }
    throw _fail('Missing "$close"');
  }

  /// Reads directives, returning the `@deprecated` reason (empty when none was
  /// given) or null when not deprecated.
  String? _directives() {
    String? deprecated;
    while (cur?.isPunct('@') == true) {
      p++;
      final name = _name();
      var reason = '';
      if (cur?.isPunct('(') == true) {
        final start = p;
        _skipBalanced('(', ')');
        if (name == 'deprecated') {
          for (var i = start; i < p; i++) {
            if (tokens[i].isName('reason') &&
                i + 2 < p &&
                tokens[i + 2].kind == GqlTok.string) {
              reason = tokens[i + 2].text;
            }
          }
        }
      }
      if (name == 'deprecated') deprecated = reason;
    }
    return deprecated;
  }
}
