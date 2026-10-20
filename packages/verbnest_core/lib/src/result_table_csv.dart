// Reading CSV and TSV as a table.
// Part of result_table.dart (the private helpers are shared).
part of 'result_table.dart';

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
