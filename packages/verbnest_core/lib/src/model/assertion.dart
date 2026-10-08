import 'dart:convert';

import '../json_path.dart';
import '../json_schema.dart';
import '../safe_regex.dart';
import '../test_result.dart';

enum AssertionTarget { status, header, jsonPath, responseTime, body, schema }

enum AssertionOp {
  eq('equals'),
  neq('does not equal'),
  lt('is less than'),
  lte('is at most'),
  gt('is greater than'),
  gte('is at least'),
  exists('exists'),
  notExists('does not exist'),
  contains('contains'),
  notContains('does not contain'),
  matches('matches regex');

  const AssertionOp(this.label);
  final String label;

  bool get needsValue => this != exists && this != notExists;
}

/// What an assertion looks at once the response is in.
class ResponseFacts {
  const ResponseFacts({
    required this.status,
    required this.headers,
    required this.body,
    required this.timeMs,
  });

  final int status;
  final List<(String, String)> headers;
  final String body;
  final int timeMs;

  String? header(String name) {
    final lower = name.toLowerCase();
    for (final (k, v) in headers) {
      if (k.toLowerCase() == lower) return v;
    }
    return null;
  }
}

/// A no-code check on a response (FR-SCR-006), stored as data and evaluated
/// by the app after each send. [name] is the header name or the JSONPath.
class Assertion {
  const Assertion({
    required this.target,
    this.op = AssertionOp.eq,
    this.name = '',
    this.value = '',
    this.enabled = true,
  });

  final AssertionTarget target;
  final AssertionOp op;
  final String name;
  final String value;
  final bool enabled;

  Assertion copyWith({
    AssertionTarget? target,
    AssertionOp? op,
    String? name,
    String? value,
    bool? enabled,
  }) => Assertion(
    target: target ?? this.target,
    op: op ?? this.op,
    name: name ?? this.name,
    value: value ?? this.value,
    enabled: enabled ?? this.enabled,
  );

  /// Operators that make sense for [target], in menu order.
  static List<AssertionOp> opsFor(AssertionTarget target) => switch (target) {
    AssertionTarget.status || AssertionTarget.responseTime => const [
      AssertionOp.eq,
      AssertionOp.neq,
      AssertionOp.lt,
      AssertionOp.lte,
      AssertionOp.gt,
      AssertionOp.gte,
    ],
    AssertionTarget.header || AssertionTarget.jsonPath => AssertionOp.values,
    AssertionTarget.body => const [
      AssertionOp.contains,
      AssertionOp.notContains,
      AssertionOp.matches,
      AssertionOp.eq,
    ],
    AssertionTarget.schema => const [AssertionOp.eq],
  };

  String get title {
    final what = switch (target) {
      AssertionTarget.status => 'Status code',
      AssertionTarget.header => 'Header $name',
      AssertionTarget.jsonPath => 'JSON $name',
      AssertionTarget.responseTime => 'Response time (ms)',
      AssertionTarget.body => 'Body',
      AssertionTarget.schema => 'Body matches JSON schema',
    };
    if (target == AssertionTarget.schema) return what;
    return op.needsValue ? '$what ${op.label} $value' : '$what ${op.label}';
  }

  Map<String, Object?> toJson() => {
    'target': target.name,
    'op': op.name,
    if (name.isNotEmpty) 'name': name,
    if (value.isNotEmpty) 'value': value,
    if (!enabled) 'enabled': false,
  };

  static Assertion? fromJson(Object? json) {
    if (json is! Map) return null;
    final target = AssertionTarget.values
        .where((t) => t.name == json['target'])
        .firstOrNull;
    if (target == null) return null;
    return Assertion(
      target: target,
      op:
          AssertionOp.values.where((o) => o.name == json['op']).firstOrNull ??
          AssertionOp.eq,
      name: json['name'] as String? ?? '',
      value: json['value'] as String? ?? '',
      enabled: json['enabled'] as bool? ?? true,
    );
  }

  static List<Assertion> listFromJson(Object? json) => [
    if (json is List)
      for (final j in json) ?fromJson(j),
  ];

  static List<Object?> listToJson(List<Assertion> list) => [
    for (final a in list) a.toJson(),
  ];

  /// Checks the response. [resolve] replaces `{{variables}}` in the name and
  /// value first. The result is a normal test result, so assertions and
  /// `pm.test` look the same in the Tests tab and in reports.
  TestResult evaluate(ResponseFacts facts, {String Function(String)? resolve}) {
    final r = resolve ?? (s) => s;
    final title = Assertion(
      target: target,
      op: op,
      name: r(name),
      value: r(value),
    ).title;
    try {
      final failure = _check(facts, r(name), r(value));
      return failure == null
          ? TestResult(name: title, status: 'pass')
          : TestResult(name: title, status: 'fail', message: failure);
    } on FormatException catch (e) {
      return TestResult(name: title, status: 'fail', message: e.message);
    }
  }

  String? _check(ResponseFacts f, String name, String value) {
    switch (target) {
      case AssertionTarget.status:
        return _numeric(f.status, value);
      case AssertionTarget.responseTime:
        return _numeric(f.timeMs, value);
      case AssertionTarget.header:
        final actual = f.header(name);
        return _compare(actual, actual != null, value, 'header "$name"');
      case AssertionTarget.body:
        return _compare(f.body, true, value, 'body');
      case AssertionTarget.jsonPath:
        Object? json;
        try {
          json = jsonDecode(f.body);
        } on FormatException {
          return 'The response body is not JSON';
        }
        final hits = jsonPath(json, name);
        return _compare(
          hits.isEmpty ? null : hits.first,
          hits.isNotEmpty,
          value,
          name,
        );
      case AssertionTarget.schema:
        Object? json, schema;
        try {
          json = jsonDecode(f.body);
        } on FormatException {
          return 'The response body is not JSON';
        }
        try {
          schema = jsonDecode(value);
        } on FormatException {
          return 'The schema is not valid JSON';
        }
        final errors = validateJsonSchema(json, schema);
        return errors.isEmpty ? null : errors.take(5).join('; ');
    }
  }

  String? _numeric(num actual, String value) {
    final expected = num.tryParse(value.trim());
    if (expected == null) throw FormatException('"$value" is not a number');
    final ok = switch (op) {
      AssertionOp.eq => actual == expected,
      AssertionOp.neq => actual != expected,
      AssertionOp.lt => actual < expected,
      AssertionOp.lte => actual <= expected,
      AssertionOp.gt => actual > expected,
      AssertionOp.gte => actual >= expected,
      _ => throw FormatException('${op.label} does not apply here'),
    };
    return ok ? null : 'Got $actual';
  }

  String? _compare(Object? actual, bool present, String value, String what) {
    if (op == AssertionOp.exists) return present ? null : '$what is missing';
    if (op == AssertionOp.notExists) {
      return present ? '$what is present' : null;
    }
    if (!present) return '$what is missing';
    final shown = _show(actual);
    switch (op) {
      case AssertionOp.eq:
        return _equals(actual, value) ? null : 'Got $shown';
      case AssertionOp.neq:
        return _equals(actual, value) ? 'Got $shown' : null;
      case AssertionOp.contains:
        return _contains(actual, value) ? null : 'Got $shown';
      case AssertionOp.notContains:
        return _contains(actual, value) ? 'Got $shown' : null;
      case AssertionOp.matches:
        final hit = safeRegexMatch(value, _text(actual));
        if (hit == null) return 'The pattern is invalid or unsafe: $value';
        return hit ? null : 'Got $shown';
      case AssertionOp.lt:
      case AssertionOp.lte:
      case AssertionOp.gt:
      case AssertionOp.gte:
        final a = actual is num ? actual : num.tryParse(_text(actual));
        if (a == null) return 'Got $shown, which is not a number';
        return _numeric(a, value);
      case AssertionOp.exists:
      case AssertionOp.notExists:
        return null;
    }
  }

  static String _text(Object? v) =>
      v is String ? v : (v is num || v is bool ? '$v' : jsonEncode(v));

  static String _show(Object? v) {
    final t = v is String ? '"$v"' : _text(v);
    return t.length > 80 ? '${t.substring(0, 77)}...' : t;
  }

  static bool _equals(Object? actual, String expected) {
    if (actual is num) return num.tryParse(expected.trim()) == actual;
    if (actual is bool) return expected.trim() == '$actual';
    if (actual == null) return expected.trim() == 'null';
    if (actual is String) return actual == expected;
    try {
      return jsonEncode(actual) == jsonEncode(jsonDecode(expected));
    } on FormatException {
      return false;
    }
  }

  static bool _contains(Object? actual, String expected) {
    if (actual is List) return actual.any((e) => _equals(e, expected));
    return _text(actual).contains(expected);
  }
}
