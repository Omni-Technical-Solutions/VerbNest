import 'dart:convert';

import 'package:verbnest_core/verbnest_core.dart';

import 'curl.dart';

/// Languages offered by "Generate code" (FR-IO-003).
enum CodeLanguage {
  curl('cURL'),
  javascriptFetch('JavaScript (fetch)'),
  pythonRequests('Python (requests)'),
  dartHttp('Dart (http)');

  const CodeLanguage(this.label);

  final String label;
}

/// Renders [item] as code in [language]. Pass [resolve] to substitute
/// variables; otherwise `{{names}}` stay in the output. [auth] is the
/// effective (inherited) auth.
String generateCode(
  CodeLanguage language,
  HttpRequestItem item, {
  Auth? auth,
  String Function(String)? resolve,
}) {
  if (language == CodeLanguage.curl) {
    return toCurl(item, auth: auth, resolve: resolve);
  }
  final p = _Plan.of(item, auth ?? item.auth, resolve ?? (s) => s);
  return switch (language) {
    CodeLanguage.javascriptFetch => _js(p),
    CodeLanguage.pythonRequests => _python(p),
    CodeLanguage.dartHttp => _dart(p),
    CodeLanguage.curl => '',
  };
}

enum _BodyKind { none, text, form, multipart }

class _Plan {
  _Plan(
    this.method,
    this.url,
    this.headers,
    this.kind,
    this.text,
    this.fields,
    this.basic,
  );

  final String method;
  final String url;
  final List<(String, String)> headers;
  final _BodyKind kind;
  final String text;
  final List<KeyValue> fields;

  /// Basic auth credentials, kept apart because encoding them is language
  /// specific.
  final (String, String)? basic;

  static _Plan of(HttpRequestItem item, Auth auth, String Function(String) r) {
    var url = r(item.url);
    final headers = <(String, String)>[
      for (final h in item.headers)
        if (h.enabled && h.key.trim().isNotEmpty) (r(h.key), r(h.value)),
    ];
    (String, String)? basic;
    switch (auth) {
      case BearerAuth(:final token):
        headers.add(('Authorization', 'Bearer ${r(token)}'));
      case BasicAuth(:final username, :final password):
        basic = (r(username), r(password));
      case ApiKeyAuth(:final key, :final value, :final addTo):
        if (addTo == ApiKeyLocation.query) {
          url += '${url.contains('?') ? '&' : '?'}${r(key)}=${r(value)}';
        } else {
          headers.add((r(key), r(value)));
        }
      default:
    }
    final hasType = headers.any((h) => h.$1.toLowerCase() == 'content-type');
    final type = item.body.defaultContentType;
    return _Plan._build(item, url, headers, basic, hasType, type, r);
  }

  static _Plan _build(
    HttpRequestItem item,
    String url,
    List<(String, String)> headers,
    (String, String)? basic,
    bool hasType,
    String? type,
    String Function(String) r,
  ) {
    var kind = _BodyKind.none;
    var text = '';
    var fields = <KeyValue>[];
    switch (item.body) {
      case GraphqlBody() && final g when g.sentInUrl(item.method):
        url = UrlText.appendQuery(
          url,
          g.toQueryString(resolve: r, lenient: true),
        );
      case RawBody(text: final t):
        kind = _BodyKind.text;
        text = r(t);
      case GraphqlBody() && final g:
        kind = _BodyKind.text;
        text = g.toPayload(resolve: r, lenient: true);
      case UrlEncodedBody(fields: final f):
        kind = _BodyKind.form;
        fields = [
          for (final x in f)
            if (x.enabled) x.copyWith(key: r(x.key), value: r(x.value)),
        ];
      case FormDataBody(fields: final f):
        kind = _BodyKind.multipart;
        fields = [
          for (final x in f)
            if (x.enabled) x.copyWith(key: r(x.key), value: r(x.value)),
        ];
      case BinaryBody() || NoBody():
    }
    if (type != null && !hasType && kind != _BodyKind.none) {
      headers.add(('Content-Type', type));
    }
    return _Plan(
      item.method.toUpperCase(),
      url,
      headers,
      kind,
      text,
      fields,
      basic,
    );
  }
}

String _js(_Plan p) {
  String q(String s) => jsonEncode(s);
  final b = StringBuffer();
  final headers = [...p.headers];
  if (p.kind == _BodyKind.multipart) {
    b.writeln('const form = new FormData();');
    for (final f in p.fields) {
      b.writeln(
        f.type == KeyValueType.file
            ? 'form.append(${q(f.key)}, /* file input or Blob for ${q(f.value).replaceAll('*/', r'*\/')} */ new Blob([]));'
            : 'form.append(${q(f.key)}, ${q(f.value)});',
      );
    }
    b.writeln();
  }
  b.writeln('const response = await fetch(${q(p.url)}, {');
  b.writeln('  method: ${q(p.method)},');
  if (headers.isNotEmpty || p.basic != null) {
    b.writeln('  headers: {');
    for (final h in headers) {
      b.writeln('    ${q(h.$1)}: ${q(h.$2)},');
    }
    if (p.basic != null) {
      b.writeln(
        "    'Authorization': 'Basic ' + btoa(${q(p.basic!.$1)} + ':' + ${q(p.basic!.$2)}),",
      );
    }
    b.writeln('  },');
  }
  switch (p.kind) {
    case _BodyKind.text:
      b.writeln('  body: ${q(p.text)},');
    case _BodyKind.form:
      b.writeln('  body: new URLSearchParams({');
      for (final f in p.fields) {
        b.writeln('    ${q(f.key)}: ${q(f.value)},');
      }
      b.writeln('  }),');
    case _BodyKind.multipart:
      b.writeln('  body: form,');
    case _BodyKind.none:
  }
  b.writeln('});');
  b.writeln('console.log(response.status, await response.text());');
  return b.toString().trimRight();
}

String _pyStr(String s) {
  final e = s
      .replaceAll(r'\', r'\\')
      .replaceAll("'", r"\'")
      .replaceAll('\n', r'\n')
      .replaceAll('\r', r'\r');
  return "'$e'";
}

String _python(_Plan p) {
  final b = StringBuffer('import requests\n\n');
  b.writeln('response = requests.request(');
  b.writeln('    ${_pyStr(p.method)},');
  b.writeln('    ${_pyStr(p.url)},');
  if (p.headers.isNotEmpty) {
    b.writeln('    headers={');
    for (final h in p.headers) {
      b.writeln('        ${_pyStr(h.$1)}: ${_pyStr(h.$2)},');
    }
    b.writeln('    },');
  }
  if (p.basic != null) {
    b.writeln('    auth=(${_pyStr(p.basic!.$1)}, ${_pyStr(p.basic!.$2)}),');
  }
  switch (p.kind) {
    case _BodyKind.text:
      b.writeln('    data=${_pyStr(p.text)}.encode(),');
    case _BodyKind.form:
      b.writeln('    data={');
      for (final f in p.fields) {
        b.writeln('        ${_pyStr(f.key)}: ${_pyStr(f.value)},');
      }
      b.writeln('    },');
    case _BodyKind.multipart:
      final files = p.fields.where((f) => f.type == KeyValueType.file);
      final plain = p.fields.where((f) => f.type != KeyValueType.file);
      if (plain.isNotEmpty) {
        b.writeln('    data={');
        for (final f in plain) {
          b.writeln('        ${_pyStr(f.key)}: ${_pyStr(f.value)},');
        }
        b.writeln('    },');
      }
      b.writeln('    files={');
      for (final f in files) {
        b.writeln(
          '        ${_pyStr(f.key)}: open(${_pyStr(f.value)}, \'rb\'),',
        );
      }
      b.writeln('    },');
    case _BodyKind.none:
  }
  b.writeln(')');
  b.writeln('print(response.status_code, response.text)');
  return b.toString().trimRight();
}

String _dartStr(String s) {
  final e = s
      .replaceAll(r'\', r'\\')
      .replaceAll("'", r"\'")
      .replaceAll(r'$', r'\$')
      .replaceAll('\n', r'\n')
      .replaceAll('\r', r'\r');
  return "'$e'";
}

String _dart(_Plan p) {
  final b = StringBuffer();
  b.writeln("import 'dart:convert';");
  b.writeln("import 'package:http/http.dart' as http;");
  b.writeln();
  b.writeln('Future<void> main() async {');
  b.writeln(
    '  final request = http.${p.kind == _BodyKind.multipart ? 'MultipartRequest' : 'Request'}(',
  );
  b.writeln('    ${_dartStr(p.method)},');
  b.writeln('    Uri.parse(${_dartStr(p.url)}),');
  b.writeln('  );');
  final headers = [...p.headers];
  if (headers.isNotEmpty || p.basic != null) {
    b.writeln('  request.headers.addAll({');
    for (final h in headers) {
      b.writeln('    ${_dartStr(h.$1)}: ${_dartStr(h.$2)},');
    }
    if (p.basic != null) {
      b.writeln(
        "    'Authorization': 'Basic \${base64Encode(utf8.encode(${_dartStr('${p.basic!.$1}:${p.basic!.$2}')}))}',",
      );
    }
    b.writeln('  });');
  }
  switch (p.kind) {
    case _BodyKind.text:
      b.writeln('  request.body = ${_dartStr(p.text)};');
    case _BodyKind.form:
      b.writeln('  request.bodyFields = {');
      for (final f in p.fields) {
        b.writeln('    ${_dartStr(f.key)}: ${_dartStr(f.value)},');
      }
      b.writeln('  };');
    case _BodyKind.multipart:
      for (final f in p.fields) {
        b.writeln(
          f.type == KeyValueType.file
              ? '  request.files.add(await http.MultipartFile.fromPath(${_dartStr(f.key)}, ${_dartStr(f.value)}));'
              : '  request.fields[${_dartStr(f.key)}] = ${_dartStr(f.value)};',
        );
      }
    case _BodyKind.none:
  }
  b.writeln(
    '  final response = await http.Response.fromStream(await request.send());',
  );
  b.writeln('  print(\'\${response.statusCode} \${response.body}\');');
  b.writeln('}');
  return b.toString().trimRight();
}
