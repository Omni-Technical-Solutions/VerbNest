import 'dart:convert';
import 'dart:typed_data';

import 'package:xml/xml.dart';
import 'package:xml/xpath.dart';

import 'json_path.dart';

/// What kind of filter expression a body takes, from its content type.
enum BodyKind { json, xml, other }

BodyKind bodyKindOf(String? contentType) {
  final t = (contentType ?? '').toLowerCase();
  if (t.contains('json')) return BodyKind.json;
  if (t.contains('xml')) return BodyKind.xml;
  return BodyKind.other;
}

/// Applies a JSONPath (JSON bodies) or XPath (XML bodies) to [text] and
/// returns the matches as text (FR-RES-004). Throws [FormatException] when the
/// body does not parse, the expression is bad, or the body has no filter.
String filterBody(String text, BodyKind kind, String expression) {
  final expr = expression.trim();
  switch (kind) {
    case BodyKind.json:
      final Object? root;
      try {
        root = jsonDecode(text);
      } on FormatException {
        throw const FormatException('The body is not valid JSON');
      }
      final matches = jsonPath(root, expr);
      const encoder = JsonEncoder.withIndent('  ');
      if (matches.isEmpty) return '';
      return encoder.convert(matches.length == 1 ? matches.single : matches);
    case BodyKind.xml:
      final XmlDocument doc;
      try {
        doc = XmlDocument.parse(text);
      } on XmlException catch (e) {
        throw FormatException('The body is not valid XML: ${e.message}');
      }
      try {
        return [
          for (final n in doc.xpath(expr))
            n is XmlElement
                ? n.toXmlString(pretty: true)
                : n.value ?? n.innerText,
        ].join('\n');
      } on Object catch (e) {
        throw FormatException('Bad XPath: $e');
      }
    case BodyKind.other:
      throw const FormatException('Only JSON and XML bodies can be filtered');
  }
}

/// A classic hex dump: offset, 16 bytes in hex, then the printable text.
/// Stops after [maxBytes] and says how much was left out, because a dump of a
/// large body would fill the screen with rows nobody reads.
String hexDump(Uint8List bytes, {int maxBytes = 64 * 1024}) {
  final shown = bytes.length < maxBytes ? bytes.length : maxBytes;
  final out = StringBuffer();
  for (var i = 0; i < shown; i += 16) {
    final end = i + 16 < shown ? i + 16 : shown;
    final row = bytes.sublist(i, end);
    final hex = [
      for (var j = 0; j < 16; j++)
        j < row.length ? row[j].toRadixString(16).padLeft(2, '0') : '  ',
    ];
    final text = String.fromCharCodes([
      for (final b in row) b >= 0x20 && b < 0x7f ? b : 0x2e,
    ]);
    out.writeln(
      '${i.toRadixString(16).padLeft(8, '0')}  '
      '${hex.sublist(0, 8).join(' ')}  ${hex.sublist(8).join(' ')}  |$text|',
    );
  }
  if (shown < bytes.length) {
    out.writeln('... ${bytes.length - shown} more bytes not shown');
  }
  return out.toString();
}
