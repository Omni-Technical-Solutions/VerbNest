import 'dart:convert';

/// Deterministic YAML for plain maps, lists, strings, numbers, bools and
/// null: map keys are sorted, strings are plain only when that is safe,
/// otherwise double-quoted with JSON escapes (a valid YAML scalar).
String emitYaml(Object? value) {
  final b = StringBuffer();
  _node(b, value, 0, inline: false);
  return b.toString();
}

final _plainSafe = RegExp(r'^[A-Za-z_][A-Za-z0-9_./-]*(?: [A-Za-z0-9_./-]+)*$');
const _reserved = {
  'true', 'false', 'null', 'yes', 'no', 'on', 'off', 'y', 'n', //
  'True', 'False', 'Null', 'Yes', 'No', 'On', 'Off', 'TRUE', 'FALSE', 'NULL',
  '~',
};

String _scalar(Object? v) {
  if (v == null) return 'null';
  if (v is bool || v is num) return '$v';
  final s = '$v';
  if (_plainSafe.hasMatch(s) && !_reserved.contains(s)) return s;
  return jsonEncode(s);
}

void _node(StringBuffer b, Object? v, int indent, {required bool inline}) {
  final pad = ' ' * indent;
  if (v is Map && v.isNotEmpty) {
    final keys = v.keys.map((k) => '$k').toList()..sort();
    var first = true;
    for (final k in keys) {
      final child = v[k];
      final lead = (first && inline) ? '' : pad;
      first = false;
      b.write('$lead${_scalar(k)}:');
      if (child is Map && child.isNotEmpty ||
          child is List && child.isNotEmpty) {
        b.writeln();
        _node(b, child, indent + 2, inline: false);
      } else {
        b.writeln(' ${_empty(child)}');
      }
    }
  } else if (v is List && v.isNotEmpty) {
    for (var i = 0; i < v.length; i++) {
      final item = v[i];
      final lead = (i == 0 && inline) ? '' : pad;
      if (item is Map && item.isNotEmpty) {
        b.write('$lead- ');
        _node(b, item, indent + 2, inline: true);
      } else if (item is List && item.isNotEmpty) {
        b.writeln('$lead-');
        _node(b, item, indent + 2, inline: false);
      } else {
        b.writeln('$lead- ${_empty(item)}');
      }
    }
  } else {
    b.writeln('$pad${_empty(v)}');
  }
}

String _empty(Object? v) =>
    v is Map && v.isEmpty ? '{}' : (v is List && v.isEmpty ? '[]' : _scalar(v));
