// Reading JSON as a table.
// Part of result_table.dart (the private helpers are shared).
part of 'result_table.dart';

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

bool _isRecords(List<dynamic> list) {
  for (final e in list) {
    if (e != null) return e is Map || e is List;
  }
  return false;
}

String _keyPath(String key) => RegExp(r'^[A-Za-z_][A-Za-z0-9_]*$').hasMatch(key)
    ? '.$key'
    : "['${key.replaceAll(r'\', r'\\').replaceAll("'", r"\'")}']";

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
      // The path is built from the keys, so it resolves; if it ever does not,
      // show the whole body as Key / Value rather than failing.
      if (hits.length == 1) {
        data = hits.single;
        label = best.path;
      }
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

ResultTable _fromObjects(
  List<Map<dynamic, dynamic>> objects,
  bool flatten,
  String label,
) {
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
