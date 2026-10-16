import 'dart:convert';

import 'package:xml/xml.dart';

import 'body_tools.dart' show BodyKind, bodyKindOf;
import 'json_path.dart';

/// What a column holds, from its non-null cells (FR-RES-008).
enum ColumnType { text, number, boolean, date, json, empty }

class TableColumn {
  const TableColumn(this.name, this.type);

  final String name;
  final ColumnType type;
}

/// A place in a JSON body that can be read as a table: [path] is a JSONPath
/// and [count] the length of the array there.
class TableSource {
  const TableSource(this.path, this.count);

  final String path;
  final int count;

  @override
  String toString() => '$path ($count)';
}

/// A read-only grid of typed values: columns and rows (FR-RES-008).
///
/// Cells are the parsed values: null, bool, num, String, or a Map / List for
/// nested JSON. The grid shows at most [maxGridRows] rows, [maxColumns] columns
/// and [maxCellChars] characters per cell; copy and export use all the rows.
class ResultTable {
  ResultTable(
    this.columns,
    this.rows, {
    this.columnsDropped = 0,
    this.label = '',
  });

  final List<TableColumn> columns;
  final List<List<Object?>> rows;

  /// Columns left out because the body had more than [maxColumns].
  final int columnsDropped;

  /// Where the rows came from, for example `$.items`.
  final String label;

  static const maxGridRows = 10000;
  static const maxColumns = 200;
  static const maxCellChars = 4000;

  int get rowCount => rows.length;
  int get columnCount => columns.length;

  /// Row indexes in the order of column [col]; stable, nulls last in either
  /// direction. Numbers sort as numbers, dates as dates, text without regard to
  /// case.
  List<int> sortOrder(int col, {required bool ascending}) {
    final type = columns[col].type;
    final order = List<int>.generate(rows.length, (i) => i);
    int compare(int a, int b) {
      final x = rows[a][col], y = rows[b][col];
      if (x == null || y == null) {
        // Nulls stay last whichever way the sort runs.
        return x == null ? (y == null ? 0 : 1) : -1;
      }
      final c = _compareValues(x, y, type);
      return ascending ? c : -c;
    }

    // List.sort is not stable, so ties fall back to the original order.
    order.sort((a, b) {
      final c = compare(a, b);
      return c != 0 ? c : a.compareTo(b);
    });
    return order;
  }

  /// Indexes of the rows where any cell contains [query] (case-insensitive).
  List<int> matchingRows(String query) {
    final q = query.trim().toLowerCase();
    if (q.isEmpty) return List<int>.generate(rows.length, (i) => i);
    return [
      for (var i = 0; i < rows.length; i++)
        if (rows[i].any((c) => cellText(c).toLowerCase().contains(q))) i,
    ];
  }

  /// The rows at [rowIndexes] and columns at [colIndexes] as tab-separated
  /// text, the form spreadsheets paste.
  String toTsv(
    List<int> rowIndexes,
    List<int> colIndexes, {
    bool header = false,
  }) {
    String cell(Object? v) =>
        cellText(v)
            .replaceAll('\t', ' ')
            .replaceAll('\r\n', ' ')
            .replaceAll('\n', ' ')
            .replaceAll('\r', ' ');
    final lines = <String>[
      if (header) colIndexes.map((c) => cell(columns[c].name)).join('\t'),
      for (final r in rowIndexes)
        colIndexes.map((c) => cell(rows[r][c])).join('\t'),
    ];
    return lines.join('\n');
  }

  /// RFC 4180 CSV: quotes where a value has a comma, quote or line break.
  String toCsv(List<int> rowIndexes, List<int> colIndexes) {
    String q(String s) =>
        s.contains(RegExp(r'[",\r\n]')) ? '"${s.replaceAll('"', '""')}"' : s;
    final lines = <String>[
      colIndexes.map((c) => q(columns[c].name)).join(','),
      for (final r in rowIndexes)
        colIndexes.map((c) => q(cellText(rows[r][c]))).join(','),
    ];
    return '${lines.join('\r\n')}\r\n';
  }

  /// The selected rows as a JSON array of objects, keeping each value's type.
  String toJson(List<int> rowIndexes, List<int> colIndexes) =>
      const JsonEncoder.withIndent('  ').convert([
        for (final r in rowIndexes)
          {for (final c in colIndexes) columns[c].name: rows[r][c]},
      ]);

  /// A GitHub-style Markdown table.
  String toMarkdown(List<int> rowIndexes, List<int> colIndexes) {
    String cell(Object? v) =>
        cellText(v).replaceAll('|', r'\|').replaceAll(RegExp(r'\r?\n'), ' ');
    final lines = <String>[
      '| ${colIndexes.map((c) => cell(columns[c].name)).join(' | ')} |',
      '| ${colIndexes.map((_) => '---').join(' | ')} |',
      for (final r in rowIndexes)
        '| ${colIndexes.map((c) => cell(rows[r][c])).join(' | ')} |',
    ];
    return lines.join('\n');
  }
}

/// A value as plain text (copy, export, search): null is empty, nested values
/// are compact JSON.
String cellText(Object? v) {
  if (v == null) return '';
  if (v is String) return v;
  if (v is num) return _numText(v);
  if (v is bool) return '$v';
  return jsonEncode(v);
}

/// A value for one line in the grid: nested objects and arrays become a short
/// summary followed by the start of their JSON.
String cellPreview(Object? v) {
  if (v == null) return 'null';
  if (v is Map) {
    return '{${v.length} ${v.length == 1 ? 'key' : 'keys'}} ${jsonEncode(v)}';
  }
  if (v is List) {
    return '[${v.length} ${v.length == 1 ? 'item' : 'items'}] ${jsonEncode(v)}';
  }
  return cellText(v);
}

/// A value in full, for the detail view: nested values are indented JSON.
String cellFull(Object? v) => v is Map || v is List
    ? const JsonEncoder.withIndent('  ').convert(v)
    : cellText(v);

String _numText(num v) {
  if (v is int) return '$v';
  if (v == v.truncateToDouble() && v.abs() < 1e15) return '${v.toInt()}';
  return '$v';
}

final _isoDate = RegExp(
  r'^\d{4}-\d{2}-\d{2}([T ]\d{2}:\d{2}(:\d{2}(\.\d+)?)?(Z|[+-]\d{2}:?\d{2})?)?$',
);

DateTime? _date(Object? v) =>
    v is String && _isoDate.hasMatch(v) ? DateTime.tryParse(v) : null;

int _compareValues(Object x, Object y, ColumnType type) {
  switch (type) {
    case ColumnType.number:
      if (x is num && y is num) return x.compareTo(y);
    case ColumnType.date:
      final a = _date(x), b = _date(y);
      if (a != null && b != null) return a.compareTo(b);
    case ColumnType.boolean:
      if (x is bool && y is bool) return (x ? 1 : 0).compareTo(y ? 1 : 0);
    case ColumnType.text || ColumnType.json || ColumnType.empty:
      break;
  }
  return cellText(x).toLowerCase().compareTo(cellText(y).toLowerCase());
}

ColumnType _typeOf(Iterable<Object?> values) {
  var seen = 0;
  var allNum = true, allBool = true, allDate = true, allString = true;
  var anyNested = false;
  for (final v in values) {
    if (v == null) continue;
    if (++seen > 1000) break;
    if (v is! num) allNum = false;
    if (v is! bool) allBool = false;
    if (_date(v) == null) allDate = false;
    if (v is! String) allString = false;
    if (v is Map || v is List) anyNested = true;
  }
  if (seen == 0) return ColumnType.empty;
  if (allNum) return ColumnType.number;
  if (allBool) return ColumnType.boolean;
  if (allDate) return ColumnType.date;
  if (anyNested) return ColumnType.json;
  return allString ? ColumnType.text : ColumnType.text;
}

ResultTable _build(List<String> names, List<List<Object?>> rows, String label) {
  final keep = names.length > ResultTable.maxColumns
      ? ResultTable.maxColumns
      : names.length;
  final cols = [
    for (var c = 0; c < keep; c++)
      TableColumn(
        names[c],
        _typeOf(rows.map((r) => c < r.length ? r[c] : null)),
      ),
  ];
  final cut = [
    for (final r in rows)
      [for (var c = 0; c < keep; c++) c < r.length ? r[c] : null],
  ];
  return ResultTable(
    cols,
    cut,
    columnsDropped: names.length - keep,
    label: label,
  );
}

// ---------------------------------------------------------------- JSON

/// Arrays in [root] that read as tables: the root itself when it is a list,
/// otherwise lists of objects or arrays found up to three levels down.
List<TableSource> findTableSources(Object? root) {
  final out = <TableSource>[];
  if (root is List) {
    if (root.isNotEmpty) out.add(TableSource(r'$', root.length));
    return out;
  }
  void walk(Object? node, String path, int depth) {
    if (node is! Map || depth > 3) return;
    for (final e in node.entries) {
      final p = '$path${_keyPath('${e.key}')}';
      final v = e.value;
      if (v is List && v.isNotEmpty && _isRecords(v)) {
        out.add(TableSource(p, v.length));
      } else if (v is Map) {
        walk(v, p, depth + 1);
      }
    }
  }

  walk(root, r'$', 1);
  return out;
}

bool _isRecords(List list) {
  for (final e in list) {
    if (e != null) return e is Map || e is List;
  }
  return false;
}

String _keyPath(String key) => RegExp(r'^[A-Za-z_][A-Za-z0-9_]*$').hasMatch(key)
    ? '.$key'
    : "['${key.replaceAll("'", r"\'")}']";

/// Reads [root] as a table, or returns null when it is not tabular.
///
/// [source] is a JSONPath naming the array to use; without it the root list,
/// or the largest list of records in the root object, is used, and a root
/// object with none becomes a Key / Value table. [flatten] turns nested
/// objects into dotted columns (three levels). [firstRowHeader] uses the first
/// row of an array of arrays as the column names.
ResultTable? tableFromJson(
  Object? root, {
  String? source,
  bool flatten = false,
  bool firstRowHeader = false,
}) {
  Object? data = root;
  var label = r'$';
  if (source != null && source.trim().isNotEmpty && source.trim() != r'$') {
    final hits = jsonPath(root, source);
    if (hits.isEmpty) return null;
    data = hits.length == 1 ? hits.single : hits;
    label = source.trim();
  } else if (root is Map) {
    final sources = findTableSources(root);
    if (sources.isNotEmpty) {
      final best = sources.reduce((a, b) => b.count > a.count ? b : a);
      final hits = jsonPath(root, best.path);
      data = hits.single;
      label = best.path;
    }
  }

  if (data is Map) {
    return _build(
      ['Key', 'Value'],
      [
        for (final e in data.entries) ['${e.key}', e.value],
      ],
      label,
    );
  }
  if (data is! List) {
    return data == null
        ? null
        : _build(
            ['Value'],
            [
              [data],
            ],
            label,
          );
  }
  if (data.isEmpty) return null;

  final items = data.where((e) => e != null).toList();
  if (items.isNotEmpty && items.every((e) => e is Map)) {
    return _fromObjects(
      [for (final e in data) e is Map ? e : const <Object?, Object?>{}],
      flatten,
      label,
    );
  }
  if (items.isNotEmpty && items.every((e) => e is List)) {
    final matrix = [for (final e in data) e is List ? e : const <Object?>[]];
    var width = 0;
    for (final r in matrix) {
      if (r.length > width) width = r.length;
    }
    if (firstRowHeader && matrix.length > 1) {
      final head = matrix.first;
      return _build(
        [
          for (var c = 0; c < width; c++)
            c < head.length && cellText(head[c]).isNotEmpty
                ? cellText(head[c])
                : '${c + 1}',
        ],
        matrix.skip(1).map((r) => [...r]).toList(),
        label,
      );
    }
    return _build(
      [for (var c = 0; c < width; c++) '${c + 1}'],
      matrix.map((r) => [...r]).toList(),
      label,
    );
  }
  return _build(
    ['Value'],
    [
      for (final e in data) [e],
    ],
    label,
  );
}

ResultTable _fromObjects(List<Map> objects, bool flatten, String label) {
  final names = <String>[];
  final index = <String, int>{};
  final records = <Map<String, Object?>>[];
  for (final o in objects) {
    final rec = <String, Object?>{};
    void put(String key, Object? v, int depth) {
      if (flatten && v is Map && v.isNotEmpty && depth < 3) {
        for (final e in v.entries) {
          put('$key.${e.key}', e.value, depth + 1);
        }
      } else {
        rec[key] = v;
      }
    }

    for (final e in o.entries) {
      put('${e.key}', e.value, 1);
    }
    for (final k in rec.keys) {
      if (!index.containsKey(k)) {
        index[k] = names.length;
        names.add(k);
      }
    }
    records.add(rec);
  }
  final rows = [
    for (final rec in records) [for (final n in names) rec[n]],
  ];
  return _build(names, rows, label);
}

// ----------------------------------------------------------------- XML

/// Reads XML as a table: the repeated child elements (the most common name
/// under the root) are rows, their attributes (named `@name`) and child
/// elements the columns. Without repeats, the root's children become a Key /
/// Value table. Returns null when the text is not XML.
ResultTable? tableFromXml(String text) {
  final XmlDocument doc;
  try {
    doc = XmlDocument.parse(text);
  } on XmlException {
    return null;
  }
  final root = doc.rootElement;
  final children = root.childElements.toList();
  if (children.isEmpty) return null;

  final counts = <String, int>{};
  for (final c in children) {
    counts[c.name.local] = (counts[c.name.local] ?? 0) + 1;
  }
  final repeated = counts.entries.where((e) => e.value > 1).toList();
  if (repeated.isEmpty) {
    return _build(
      ['Key', 'Value'],
      [
        for (final c in children) [c.name.local, _xmlValue(c)],
      ],
      '/${root.name.local}',
    );
  }
  final name = repeated.reduce((a, b) => b.value > a.value ? b : a).key;
  final records = children.where((c) => c.name.local == name).toList();
  final names = <String>[];
  final index = <String, int>{};
  final maps = <Map<String, Object?>>[];
  for (final r in records) {
    final m = <String, Object?>{};
    for (final a in r.attributes) {
      m['@${a.name.local}'] = a.value;
    }
    for (final c in r.childElements) {
      m[c.name.local] = _xmlValue(c);
    }
    if (r.childElements.isEmpty && r.innerText.trim().isNotEmpty) {
      m['text'] = r.innerText.trim();
    }
    for (final k in m.keys) {
      if (!index.containsKey(k)) {
        index[k] = names.length;
        names.add(k);
      }
    }
    maps.add(m);
  }
  return _build(names, [
    for (final m in maps) [for (final n in names) m[n]],
  ], '/${root.name.local}/$name');
}

Object? _xmlValue(XmlElement e) {
  if (e.childElements.isEmpty && e.attributes.isEmpty) {
    final t = e.innerText.trim();
    return t.isEmpty ? null : t;
  }
  return {
    for (final a in e.attributes) '@${a.name.local}': a.value,
    for (final c in e.childElements) c.name.local: _xmlValue(c),
  };
}

// ----------------------------------------------------------------- CSV

/// Splits CSV / TSV text into rows of cells: quotes, doubled quotes and line
/// breaks inside quotes are handled; a BOM is dropped.
List<List<String>> parseCsvRows(String text, {String delimiter = ','}) {
  final src = text.startsWith('﻿') ? text.substring(1) : text;
  final rows = <List<String>>[];
  var row = <String>[];
  final cell = StringBuffer();
  var quoted = false;
  var any = false;
  void endCell() {
    row.add(cell.toString());
    cell.clear();
  }

  void endRow() {
    endCell();
    rows.add(row);
    row = <String>[];
    any = false;
  }

  for (var i = 0; i < src.length; i++) {
    final ch = src[i];
    if (quoted) {
      if (ch == '"') {
        if (i + 1 < src.length && src[i + 1] == '"') {
          cell.write('"');
          i++;
        } else {
          quoted = false;
        }
      } else {
        cell.write(ch);
      }
      continue;
    }
    if (ch == '"' && cell.isEmpty) {
      quoted = true;
      any = true;
    } else if (ch == delimiter) {
      endCell();
      any = true;
    } else if (ch == '\r' || ch == '\n') {
      if (ch == '\r' && i + 1 < src.length && src[i + 1] == '\n') i++;
      if (any || cell.isNotEmpty || row.isNotEmpty) endRow();
    } else {
      cell.write(ch);
      any = true;
    }
  }
  if (any || cell.isNotEmpty || row.isNotEmpty) endRow();
  return rows;
}

/// Reads CSV or TSV as a table; the first row is the header unless [header]
/// is false. Short rows are padded. Returns null for empty text.
ResultTable? tableFromCsv(
  String text, {
  String delimiter = ',',
  bool header = true,
}) {
  final raw = parseCsvRows(text, delimiter: delimiter);
  if (raw.isEmpty) return null;
  var width = 0;
  for (final r in raw) {
    if (r.length > width) width = r.length;
  }
  final names = header
      ? [
          for (var c = 0; c < width; c++)
            c < raw.first.length && raw.first[c].isNotEmpty
                ? raw.first[c]
                : '${c + 1}',
        ]
      : [for (var c = 0; c < width; c++) '${c + 1}'];
  final body = header ? raw.skip(1) : raw;
  return _build(names, [
    for (final r in body)
      [for (var c = 0; c < width; c++) c < r.length ? r[c] : null],
  ], delimiter == '\t' ? 'tsv' : 'csv');
}

// ------------------------------------------------------------ dispatch

/// Reads a response body as a table when its content type allows it: JSON,
/// XML, CSV or TSV. Returns null for anything else or a body that does not
/// parse. [source], [flatten] and [firstRowHeader] apply to JSON.
ResultTable? tableFromBody(
  String text,
  String? contentType, {
  String? source,
  bool flatten = false,
  bool firstRowHeader = false,
}) {
  final type = (contentType ?? '').toLowerCase();
  if (type.contains('csv')) return tableFromCsv(text);
  if (type.contains('tab-separated')) {
    return tableFromCsv(text, delimiter: '\t');
  }
  switch (bodyKindOf(type)) {
    case BodyKind.json:
      final Object? root;
      try {
        root = jsonDecode(text);
      } on FormatException {
        return null;
      }
      try {
        return tableFromJson(
          root,
          source: source,
          flatten: flatten,
          firstRowHeader: firstRowHeader,
        );
      } on FormatException {
        return null;
      }
    case BodyKind.xml:
      return tableFromXml(text);
    case BodyKind.other:
      return null;
  }
}
