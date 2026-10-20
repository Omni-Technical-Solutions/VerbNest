// Reading a response body as a table, off the main isolate when it is large.
// Part of result_table.dart (the private helpers are shared).
part of 'result_table.dart';

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
