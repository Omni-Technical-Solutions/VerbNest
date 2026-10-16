import 'dart:convert';
import 'dart:isolate';

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
  ResultTable(this.columns, this.rows, {this.label = ''});

  final List<TableColumn> columns;
  final List<List<Object?>> rows;

  /// Where the rows came from, for example `$.items`.
  final String label;

  /// Columns the grid does not draw because there are more than
  /// [maxColumns]. They are still in the data: search, copy and export have
  /// every column.
  int get columnsDropped =>
      columns.length > maxColumns ? columns.length - maxColumns : 0;

  static const maxGridRows = 10000;
  static const maxColumns = 200;
  static const maxCellChars = 4000;

  int get rowCount => rows.length;
  int get columnCount => columns.length;

  /// Row indexes in the order of column [col]; stable, nulls last in either
  /// direction. Numbers sort as numbers, dates as dates, text without regard to
  /// case. The sort keys are worked out once, not on every comparison, which
  /// keeps 100,000 rows fast.
  List<int> sortOrder(int col, {required bool ascending}) {
    final type = columns[col].type;
    final n = rows.length;
    final keys = List<Object?>.filled(n, null);
    for (var i = 0; i < n; i++) {
      final v = rows[i][col];
      if (v == null) continue;
      keys[i] = switch (type) {
        ColumnType.number when v is num => v,
        ColumnType.date => _date(v) ?? cellText(v).toLowerCase(),
        ColumnType.boolean when v is bool => v ? 1 : 0,
        _ => cellText(v).toLowerCase(),
      };
    }
    final order = List<int>.generate(n, (i) => i);
    // List.sort is not stable, so ties fall back to the original order.
    order.sort((a, b) {
      final x = keys[a], y = keys[b];
      if (x == null || y == null) {
        // Nulls stay last whichever way the sort runs.
        return x == null ? (y == null ? a.compareTo(b) : 1) : -1;
      }
      var c = _compareKeys(x, y);
      if (!ascending) c = -c;
      return c != 0 ? c : a.compareTo(b);
    });
    return order;
  }

  List<String>? _rowText;

  /// Indexes of the rows where any cell contains [query] (case-insensitive).
  /// The lower-cased text of each row is built once, on the first search, so
  /// each later keystroke is one `contains` per row.
  List<int> matchingRows(String query) {
    final q = query.trim().toLowerCase();
    if (q.isEmpty) return List<int>.generate(rows.length, (i) => i);
    final text = _rowText ??= [
      for (final r in rows) r.map(cellText).join('\u0001').toLowerCase(),
    ];
    return [
      for (var i = 0; i < text.length; i++)
        if (text[i].contains(q)) i,
    ];
  }

  /// The rows at [rowIndexes] and columns at [colIndexes] as tab-separated
  /// text, the form spreadsheets paste.
  String toTsv(
    List<int> rowIndexes,
    List<int> colIndexes, {
    bool header = false,
  }) {
    final b = StringBuffer();
    void cell(Object? v) {
      final t = cellText(v);
      b.write(t.contains(_tsvBreak) ? t.replaceAll(_tsvBreak, ' ') : t);
    }

    void line(Object? Function(int) at) {
      var first = true;
      for (final c in colIndexes) {
        if (!first) b.write('\t');
        first = false;
        cell(at(c));
      }
    }

    var any = false;
    if (header) {
      line((c) => columns[c].name);
      any = true;
    }
    for (final r in rowIndexes) {
      if (any) b.write('\n');
      any = true;
      line((c) => rows[r][c]);
    }
    return b.toString();
  }

  /// RFC 4180 CSV: quotes where a value has a comma, quote or line break.
  String toCsv(List<int> rowIndexes, List<int> colIndexes) {
    final b = StringBuffer();
    void cell(String s) {
      if (_csvSpecial.hasMatch(s)) {
        b
          ..write('"')
          ..write(s.replaceAll('"', '""'))
          ..write('"');
      } else {
        b.write(s);
      }
    }

    var first = true;
    for (final c in colIndexes) {
      if (!first) b.write(',');
      first = false;
      cell(columns[c].name);
    }
    b.write('\r\n');
    for (final r in rowIndexes) {
      first = true;
      final row = rows[r];
      for (final c in colIndexes) {
        if (!first) b.write(',');
        first = false;
        cell(cellText(row[c]));
      }
      b.write('\r\n');
    }
    return b.toString();
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

final _tsvBreak = RegExp(r'[\t\r\n]+');
final _csvSpecial = RegExp(r'[",\r\n]');

int _compareKeys(Object x, Object y) {
  if (x is num && y is num) return x.compareTo(y);
  if (x is DateTime && y is DateTime) return x.compareTo(y);
  // Mixed kinds in one column: compare as text.
  return '$x'.compareTo('$y');
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

/// A number as it was written: 10.0 stays 10.0, not 10.
String _numText(num v) => '$v';

final _isoDate = RegExp(
  r'^\d{4}-\d{2}-\d{2}([T ]\d{2}:\d{2}(:\d{2}(\.\d+)?)?(Z|[+-]\d{2}:?\d{2})?)?$',
);

DateTime? _date(Object? v) =>
    v is String && _isoDate.hasMatch(v) ? DateTime.tryParse(v) : null;

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
  final cols = [
    for (var c = 0; c < names.length; c++)
      TableColumn(
        names[c],
        _typeOf(rows.map((r) => c < r.length ? r[c] : null)),
      ),
  ];
  // Ragged rows are padded; nothing is cut.
  final padded = [
    for (final r in rows)
      r.length == names.length
          ? r
          : [for (var c = 0; c < names.length; c++) c < r.length ? r[c] : null],
  ];
  return ResultTable(cols, padded, label: label);
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
  if (source != null && source.trim() == r'$') {
    // The whole body: for an object, every field (so values beside the rows
    // are not left out), with lists and nested objects as values.
    data = root;
    label = r'$';
  } else if (source != null && source.trim().isNotEmpty) {
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
  // A bare number, string or boolean is not a table.
  if (data is! List) return null;
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
        // A literal key that collides with a flattened one gets a suffix
        // rather than overwriting it.
        var k = key;
        for (var n = 2; rec.containsKey(k); n++) {
          k = '$key ($n)';
        }
        rec[k] = v;
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
/// under the root, or the one named by [source], a path like `/r/item`) are
/// rows, their attributes (named `@name`), child elements and loose text the
/// columns. With [source] `$`, or when nothing repeats, the whole document is a
/// Key / Value table: the root's attributes and every child element, so
/// nothing beside the rows is left out. Returns null when the text is not XML.
ResultTable? tableFromXml(String text, {String? source}) {
  final doc = _parseXml(text);
  return doc == null ? null : _xmlTable(doc.rootElement, source);
}

XmlDocument? _parseXml(String text) {
  try {
    return XmlDocument.parse(text);
  } on XmlException {
    return null;
  }
}

/// The repeated elements under the root (as paths), then the whole document.
List<TableSource> _xmlSources(XmlElement root) {
  final counts = <String, int>{};
  for (final c in root.childElements) {
    counts[c.name.local] = (counts[c.name.local] ?? 0) + 1;
  }
  final repeated = counts.entries.where((e) => e.value > 1).toList();
  if (repeated.isEmpty) return const [];
  return [
    for (final e in repeated)
      TableSource('/${root.name.local}/${e.key}', e.value),
    TableSource(r'$', root.attributes.length + root.childElements.length),
  ];
}

ResultTable? _xmlTable(XmlElement root, String? source) {
  final children = root.childElements.toList();
  final attrs = root.attributes.toList();
  if (children.isEmpty && attrs.isEmpty) return null;
  final sources = _xmlSources(root);
  ResultTable whole() => _build(
    ['Key', 'Value'],
    [
      for (final a in attrs) ['@${a.name.local}', a.value],
      for (final c in children) [c.name.local, _xmlValue(c)],
    ],
    '/${root.name.local}',
  );

  if (source != null && source.trim() == r'$') return whole();
  if (sources.isEmpty) return whole();
  // The named group, or the most common one.
  final groups = sources.where((s) => s.path != r'$').toList();
  final pick = groups.firstWhere(
    (s) => s.path == source,
    orElse: () => groups.reduce((a, b) => b.count > a.count ? b : a),
  );
  final name = pick.path.substring(pick.path.lastIndexOf('/') + 1);
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
    final loose = _directText(r);
    if (loose.isNotEmpty) {
      // Text beside child elements keeps its own column; a leaf's text is
      // just its text.
      m[r.childElements.isEmpty ? 'text' : '#text'] = loose;
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
  ], pick.path);
}

/// The text written directly inside [e], not that of its child elements.
String _directText(XmlElement e) {
  final parts = <String>[];
  for (final n in e.nodes) {
    final t = n is XmlText
        ? n.value
        : n is XmlCDATA
        ? n.value
        : '';
    if (t.trim().isNotEmpty) parts.add(t.trim());
  }
  return parts.join(' ');
}

Object? _xmlValue(XmlElement e) {
  if (e.childElements.isEmpty && e.attributes.isEmpty) {
    final t = e.innerText.trim();
    return t.isEmpty ? null : t;
  }
  final loose = _directText(e);
  return {
    for (final a in e.attributes) '@${a.name.local}': a.value,
    for (final c in e.childElements) c.name.local: _xmlValue(c),
    if (loose.isNotEmpty) '#text': loose,
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

// ------------------------------------------------------------- reading

/// A body read as a table: the table (or null when it is not tabular), the
/// arrays it could have been read from, and whether it is an array of arrays
/// (which can take its first row as the header).
class TableReading {
  const TableReading(this.table, this.sources, this.matrix);

  static const none = TableReading(null, <TableSource>[], false);

  final ResultTable? table;
  final List<TableSource> sources;
  final bool matrix;
}

/// Bodies over this many characters are read in another isolate, so the screen
/// does not stall while a large response is parsed.
const tableIsolateThreshold = 256 * 1024;

/// The largest body offered as a table.
const tableMaxBytes = 5 * 1024 * 1024;

/// A cheap guess, before any parsing, of whether [text] can be a table: CSV and
/// TSV and XML by content type, JSON when it starts with `[` or `{`.
bool looksTabular(String? contentType, String text) {
  final type = (contentType ?? '').toLowerCase();
  if (type.contains('csv') || type.contains('tab-separated')) return true;
  if (type.contains('xml')) return true;
  if (!type.contains('json')) return false;
  for (var i = 0; i < text.length && i < 64; i++) {
    final c = text.codeUnitAt(i);
    if (c == 0x20 || c == 0x0A || c == 0x0D || c == 0x09 || c == 0xFEFF) {
      continue;
    }
    return c == 0x5B || c == 0x7B;
  }
  return false;
}

/// Reads [text] as a table, with the extra facts the response view needs
/// (the candidate arrays and whether it is a matrix). [source], [flatten] and
/// [firstRowHeader] apply to JSON.
TableReading readTable(
  String text,
  String? contentType, {
  String? source,
  bool flatten = false,
  bool firstRowHeader = false,
}) {
  if (text.isEmpty) return TableReading.none;
  final type = (contentType ?? '').toLowerCase();
  if (type.contains('xml') && !type.contains('json')) {
    final doc = _parseXml(text);
    if (doc == null) return TableReading.none;
    final sources = _xmlSources(doc.rootElement);
    final chosen = sources.any((e) => e.path == source) ? source : null;
    return TableReading(_xmlTable(doc.rootElement, chosen), sources, false);
  }
  if (!type.contains('json')) {
    return TableReading(tableFromBody(text, contentType), const [], false);
  }
  final Object? root;
  try {
    root = jsonDecode(text);
  } on FormatException {
    return TableReading.none;
  }
  // For an object the whole body is also a source, so fields beside the rows
  // (page, total, links) can be seen too.
  final sources = root is Map
      ? [TableSource(r'$', root.length), ...findTableSources(root)]
      : <TableSource>[];
  final chosen = sources.any((e) => e.path == source) ? source : null;
  final matrix =
      root is List &&
      root.isNotEmpty &&
      root.every((e) => e == null || e is List) &&
      root.any((e) => e is List);
  ResultTable? table;
  try {
    table = tableFromJson(
      root,
      source: chosen,
      flatten: flatten,
      firstRowHeader: firstRowHeader,
    );
  } on FormatException {
    table = null;
  }
  return TableReading(table, sources, matrix);
}

/// [readTable], in another isolate when [text] is over
/// [tableIsolateThreshold] characters.
Future<TableReading> readTableAsync(
  String text,
  String? contentType, {
  String? source,
  bool flatten = false,
  bool firstRowHeader = false,
}) {
  TableReading read() => readTable(
    text,
    contentType,
    source: source,
    flatten: flatten,
    firstRowHeader: firstRowHeader,
  );
  if (text.length <= tableIsolateThreshold) return Future.value(read());
  return Isolate.run(read);
}
