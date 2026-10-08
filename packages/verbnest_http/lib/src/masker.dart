import 'dart:convert';

/// Hides secrets in anything that is displayed, logged or stored
/// (constitution VII.3, FR-AUTH-006).
class Masker {
  Masker({
    Iterable<String> secretValues = const [],
    Iterable<String> sensitiveHeaders = const [],
  }) : _secrets = ({
         for (final s in secretValues)
           if (s.isNotEmpty) ...{
             s,
             // The same secret appears percent-encoded in URLs and forms.
             Uri.encodeComponent(s),
             Uri.encodeQueryComponent(s),
             jsonEncode(s).substring(1, jsonEncode(s).length - 1),
           },
       }.toList()..sort((a, b) => b.length.compareTo(a.length))),
       _headers = {
         'authorization',
         'proxy-authorization',
         'cookie',
         'set-cookie',
         'x-api-key',
         'x-auth-token',
         'x-csrf-token',
         'x-amz-security-token',
         for (final h in sensitiveHeaders) h.toLowerCase(),
       };

  static const placeholder = '••••••';

  final List<String> _secrets;
  final Set<String> _headers;

  /// Replaces secret values anywhere in [text]. Longer secrets go first so a
  /// secret that contains another is hidden as a whole.
  String maskText(String text) {
    var out = text;
    for (final s in _secrets) {
      out = out.replaceAll(s, placeholder);
    }
    return out;
  }

  bool isSensitiveHeader(String name) => _headers.contains(name.toLowerCase());

  String headerValue(String name, String value) =>
      isSensitiveHeader(name) ? placeholder : maskText(value);

  /// Masks a raw HTTP head (request line plus headers).
  String maskHead(String head) {
    final lines = head.split('\r\n');
    return [
      for (var i = 0; i < lines.length; i++)
        if (i == 0) maskText(lines[i]) else _maskHeaderLine(lines[i]),
    ].join('\r\n');
  }

  String _maskHeaderLine(String line) {
    final colon = line.indexOf(':');
    if (colon <= 0) return line;
    final name = line.substring(0, colon);
    final value = line.substring(colon + 1).trim();
    return '$name: ${headerValue(name, value)}';
  }
}
