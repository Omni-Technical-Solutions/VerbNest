import 'dart:convert';

import 'package:verbnest_core/verbnest_core.dart'
    show
        BodyKind,
        ResultTable,
        TableReading,
        TableSource,
        filterBody,
        looksTabular,
        readTable,
        readTableAsync,
        tableIsolateThreshold,
        tableMaxBytes;
import 'package:verbnest_http/verbnest_http.dart';

/// Pretty-prints JSON for display only; the stored bytes are untouched.
String prettyBody(HttpResponseRecord r) {
  final text = r.bodyText;
  final type = r.header('content-type')?.toLowerCase() ?? '';
  if (type.contains('json')) {
    try {
      return const JsonEncoder.withIndent('  ').convert(jsonDecode(text));
    } on FormatException {
      return text;
    }
  }
  return text;
}

/// What the response view works out from a body, kept until the response or
/// an option changes: typing in the search box rebuilds the view on every
/// key, and pretty-printing, filtering or reading a table of a large body is
/// slow.
class ResponseBodyCache {
  HttpResponseRecord? _textFor;
  bool? _textPretty;
  String _text = '';

  /// The body as text, pretty-printed when [pretty].
  String text(HttpResponseRecord r, {required bool pretty}) {
    if (!identical(_textFor, r) || _textPretty != pretty) {
      _textFor = r;
      _textPretty = pretty;
      _text = pretty ? prettyBody(r) : r.bodyText;
    }
    return _text;
  }

  HttpResponseRecord? _filteredFor;
  String? _filteredBy;
  String _filtered = '';

  /// Why the last [filtered] expression failed, or null.
  String? filterError;

  /// JSONPath/XPath over a large body is slow, so keep the result until the
  /// response or the expression changes.
  String filtered(HttpResponseRecord r, BodyKind kind, String filter) {
    if (!identical(_filteredFor, r) || _filteredBy != filter) {
      _filteredFor = r;
      _filteredBy = filter;
      try {
        _filtered = filterBody(r.bodyText, kind, filter);
        filterError = null;
      } on FormatException catch (e) {
        _filtered = '';
        filterError = e.message;
      }
    }
    return _filtered;
  }

  TableInfo? _tableCache;
  String? _tableKey;

  /// The body read as a table, or none. A small body is read at once. A large
  /// one is not read until the Table view is chosen ([tableOn]), and then in
  /// another isolate, so the screen does not stall; [onReady] is called when
  /// that read is done. Until then the segment is offered on a cheap guess.
  /// Bodies over [tableMaxBytes] are not offered a table.
  TableInfo table(
    HttpResponseRecord r,
    String text,
    BodyKind kind, {
    required String? source,
    required bool flatten,
    required bool headerRow,
    required bool tableOn,
    required void Function() onReady,
  }) {
    final filtered = text != r.bodyText && kind == BodyKind.json;
    final ct = filtered ? 'application/json' : r.header('content-type');
    final large = text.length > tableIsolateThreshold;
    final key =
        '${text.hashCode}|${text.length}|$ct|$source|$flatten|$headerRow|${large && tableOn}';
    if (_tableKey == key && _tableCache != null) return _tableCache!;
    _tableKey = key;
    if (r.body.length > tableMaxBytes || text.isEmpty) {
      return _tableCache = const TableInfo();
    }
    if (!large) {
      return _tableCache = TableInfo.from(
        readTable(
          text,
          ct,
          source: source,
          flatten: flatten,
          firstRowHeader: headerRow,
        ),
        asked: false,
      );
    }
    if (!looksTabular(ct, text)) return _tableCache = const TableInfo();
    if (!tableOn) return _tableCache = const TableInfo(guess: true);
    readTableAsync(
      text,
      ct,
      source: source,
      flatten: flatten,
      firstRowHeader: headerRow,
    ).then((reading) {
      // The body or an option may have changed while it was being read.
      if (_tableKey != key) return;
      _tableCache = TableInfo.from(reading, asked: true);
      onReady();
    });
    return _tableCache = const TableInfo(loading: true);
  }
}

/// A body read as a table, with the arrays it could be read from and whether it
/// is an array of arrays (which can take its first row as the header). A large
/// body is [guess]ed tabular, then [loading] while it is read in another
/// isolate; a body that turns out not to be a table is [failed].
class TableInfo {
  const TableInfo({
    this.table,
    this.sources = const [],
    this.matrix = false,
    this.loading = false,
    this.guess = false,
    this.failed = false,
  });

  /// [asked] is true when the person chose the Table view of a large body: a
  /// failed read is then reported. A small body that is not a table simply has
  /// no Table view.
  factory TableInfo.from(TableReading r, {required bool asked}) =>
      r.table == null
      ? (asked ? const TableInfo(failed: true) : const TableInfo())
      : TableInfo(table: r.table, sources: r.sources, matrix: r.matrix);

  final ResultTable? table;
  final List<TableSource> sources;
  final bool matrix;
  final bool loading;
  final bool guess;
  final bool failed;

  /// Whether the Table view is on offer.
  bool get canTable => table != null || loading || guess || failed;
}
