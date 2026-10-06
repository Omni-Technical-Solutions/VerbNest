import 'dart:convert';

/// Rows for a collection run: each row becomes the `data` scope of one
/// iteration (FR-RUN-001). Every value is text.
typedef DataRow = Map<String, String>;

/// Parses CSV (first line = names; quotes, escaped quotes and newlines inside
/// quotes are supported) or a JSON array of objects. The kind is picked by
/// [fileName] and, failing that, by the first character.
List<DataRow> parseDataFile(String text, {String fileName = ''}) {
  final body = text.startsWith('\uFEFF') ? text.substring(1) : text;
  final lower = fileName.toLowerCase();
  final looksJson = body.trimLeft().startsWith('[');
  if (lower.endsWith('.json') || (!lower.endsWith('.csv') && looksJson)) {
    return _json(body);
  }
  return _csv(body);
}

List<DataRow> _json(String text) {
  final Object? doc;
  try {
    doc = jsonDecode(text);
  } on FormatException catch (e) {
    throw FormatException('Not valid JSON: ${e.message}');
  }
  if (doc is! List) {
    throw const FormatException('A JSON data file is an array of objects');
  }
  return [
    for (final row in doc)
      if (row is Map)
        {
          for (final e in row.entries)
            '${e.key}': e.value is String
                ? e.value as String
                : (e.value is num || e.value is bool || e.value == null
                      ? '${e.value ?? ''}'
                      : jsonEncode(e.value)),
        }
      else
        throw const FormatException('Every item must be an object'),
  ];
}

List<DataRow> _csv(String text) {
  final rows = <List<String>>[];
  var row = <String>[];
  final field = StringBuffer();
  var quoted = false;
  var any = false;
  void endField() {
    row.add(field.toString());
    field.clear();
    any = true;
  }

  void endRow() {
    if (any || field.isNotEmpty) endField();
    if (row.isNotEmpty && !(row.length == 1 && row.first.isEmpty)) {
      rows.add(row);
    }
    row = <String>[];
    any = false;
  }

  for (var i = 0; i < text.length; i++) {
    final c = text[i];
    if (quoted) {
      if (c == '"') {
        if (i + 1 < text.length && text[i + 1] == '"') {
          field.write('"');
          i++;
        } else {
          quoted = false;
        }
      } else {
        field.write(c);
      }
    } else if (c == '"' && field.isEmpty) {
      quoted = true;
      any = true;
    } else if (c == ',') {
      endField();
    } else if (c == '\n' || c == '\r') {
      if (c == '\r' && i + 1 < text.length && text[i + 1] == '\n') i++;
      endRow();
    } else {
      field.write(c);
    }
  }
  if (quoted) throw const FormatException('A quoted CSV field is not closed');
  endRow();

  if (rows.isEmpty) return const [];
  final names = rows.first.map((n) => n.trim()).toList();
  if (names.any((n) => n.isEmpty)) {
    throw const FormatException('Every CSV column needs a name in line 1');
  }
  return [
    for (final r in rows.skip(1))
      {
        for (var i = 0; i < names.length; i++)
          names[i]: i < r.length ? r[i] : '',
      },
  ];
}
