// Reading XML as a table.
// Part of result_table.dart (the private helpers are shared).
part of 'result_table.dart';

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
