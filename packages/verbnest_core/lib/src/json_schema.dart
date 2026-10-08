import 'dart:convert';

import 'safe_regex.dart';

/// Checks [value] against a JSON Schema subset and returns one message per
/// problem (empty = valid). Supported: type, enum, const, required,
/// properties, additionalProperties (false), items, minItems, maxItems,
/// minimum, maximum, minLength, maxLength, pattern, oneOf, anyOf, allOf.
/// Unknown keywords are ignored.
List<String> validateJsonSchema(Object? value, Object? schema) {
  final errors = <String>[];
  _check(value, schema, r'$', errors);
  return errors;
}

bool _typeMatches(Object? v, String type) => switch (type) {
  'string' => v is String,
  'number' => v is num,
  'integer' => v is int || (v is double && v == v.truncateToDouble()),
  'boolean' => v is bool,
  'null' => v == null,
  'array' => v is List,
  'object' => v is Map,
  _ => true,
};

String _typeName(Object? v) => switch (v) {
  null => 'null',
  String() => 'string',
  bool() => 'boolean',
  int() => 'integer',
  num() => 'number',
  List() => 'array',
  Map() => 'object',
  _ => v.runtimeType.toString(),
};

bool _equal(Object? a, Object? b) => jsonEncode(a) == jsonEncode(b);

void _check(Object? v, Object? schema, String at, List<String> errors) {
  if (schema is bool) {
    if (!schema) errors.add('$at: no value is allowed here');
    return;
  }
  if (schema is! Map) return;

  final type = schema['type'];
  if (type != null) {
    final types = type is List ? type.cast<String>() : [type as String];
    if (!types.any((t) => _typeMatches(v, t))) {
      errors.add('$at: expected ${types.join(' or ')} but got ${_typeName(v)}');
      return;
    }
  }
  final en = schema['enum'];
  if (en is List && !en.any((e) => _equal(e, v))) {
    errors.add('$at: ${jsonEncode(v)} is not one of ${jsonEncode(en)}');
  }
  if (schema.containsKey('const') && !_equal(schema['const'], v)) {
    errors.add('$at: expected ${jsonEncode(schema['const'])}');
  }
  if (v is num) _checkNumber(v, schema, at, errors);
  if (v is String) _checkString(v, schema, at, errors);
  if (v is List) _checkList(v, schema, at, errors);
  if (v is Map) _checkMap(v, schema, at, errors);
  final allOf = schema['allOf'];
  if (allOf is List) {
    for (final s in allOf) {
      _check(v, s, at, errors);
    }
  }
  final anyOf = schema['anyOf'];
  if (anyOf is List && !anyOf.any((s) => validateJsonSchema(v, s).isEmpty)) {
    errors.add('$at: matches none of the anyOf schemas');
  }
  final oneOf = schema['oneOf'];
  if (oneOf is List) {
    final n = oneOf.where((s) => validateJsonSchema(v, s).isEmpty).length;
    if (n != 1) errors.add('$at: matches $n of the oneOf schemas, expected 1');
  }
}

void _checkNumber(num v, Map schema, String at, List<String> errors) {
  final min = schema['minimum'], max = schema['maximum'];
  if (min is num && v < min) errors.add('$at: $v is below minimum $min');
  if (max is num && v > max) errors.add('$at: $v is above maximum $max');
}

void _checkString(String v, Map schema, String at, List<String> errors) {
  final min = schema['minLength'], max = schema['maxLength'];
  if (min is int && v.length < min) {
    errors.add('$at: shorter than $min characters');
  }
  if (max is int && v.length > max) {
    errors.add('$at: longer than $max characters');
  }
  final pattern = schema['pattern'];
  if (pattern is String) {
    final hit = safeRegexMatch(pattern, v);
    if (hit == null) {
      errors.add('$at: pattern $pattern is invalid or unsafe');
    } else if (!hit) {
      errors.add('$at: does not match $pattern');
    }
  }
}

void _checkList(List v, Map schema, String at, List<String> errors) {
  final min = schema['minItems'], max = schema['maxItems'];
  if (min is int && v.length < min) {
    errors.add('$at: fewer than $min items');
  }
  if (max is int && v.length > max) errors.add('$at: more than $max items');
  final items = schema['items'];
  if (items != null) {
    for (var i = 0; i < v.length; i++) {
      _check(v[i], items, '$at[$i]', errors);
    }
  }
}

void _checkMap(Map v, Map schema, String at, List<String> errors) {
  final required = schema['required'];
  if (required is List) {
    for (final r in required) {
      if (!v.containsKey(r)) errors.add('$at: missing required "$r"');
    }
  }
  final props = schema['properties'];
  if (props is Map) {
    for (final e in props.entries) {
      if (v.containsKey(e.key)) {
        _check(v[e.key], e.value, '$at.${e.key}', errors);
      }
    }
    if (schema['additionalProperties'] == false) {
      for (final k in v.keys) {
        if (!props.containsKey(k)) errors.add('$at: unexpected "$k"');
      }
    }
  }
}
