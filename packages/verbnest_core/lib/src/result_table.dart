import 'dart:convert';
import 'dart:isolate';

import 'package:xml/xml.dart';

import 'body_tools.dart' show BodyKind, bodyKindOf;
import 'json_path.dart';

part 'result_table_json.dart';
part 'result_table_xml.dart';
part 'result_table_csv.dart';
part 'result_table_read.dart';

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
