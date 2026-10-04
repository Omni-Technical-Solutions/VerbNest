import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:postit_core/postit_core.dart';

import 'masker.dart';
import 'models.dart';

/// The request could not be built (bad URL, missing file, ...).
class RequestBuildError implements Exception {
  const RequestBuildError(this.message);

  final String message;

  @override
  String toString() => message;
}

/// Reads a file or attachment referenced by a request body.
typedef FileReader = Future<List<int>> Function(String reference);

/// A request ready to send, plus what the UI needs to warn the user first.
class PreparedRequest {
  PreparedRequest({
    required this.spec,
    required this.unresolved,
    required this.secretNames,
    required this.masker,
    required this.warnings,
  });

  final HttpRequestSpec spec;

  /// `{{names}}` no scope defines (FR-VAR-006).
  final Set<String> unresolved;
  final Set<String> secretNames;

  /// Hides this request's secrets in anything shown or stored.
  final Masker masker;

  /// Non-fatal notes, e.g. an auth type this version cannot apply.
  final List<String> warnings;
}

/// Turns a stored [HttpRequestItem] into a sendable [HttpRequestSpec]:
/// variable substitution, path variables, auth, bodies and settings.
class RequestBuilder {
  RequestBuilder({
    this.defaults = const HttpSettings(),
    this.readFile,
    Random? random,
  }) : _random = random ?? Random.secure();

  /// Workspace-level defaults that per-request settings override.
  final HttpSettings defaults;
  final FileReader? readFile;
  final Random _random;

  /// [auth] is the already-inherited effective auth (see `effectiveAuth`).
  Future<PreparedRequest> build(
    HttpRequestItem item,
    VariableResolver resolver, {
    Auth? auth,
  }) async {
    final ctx = _Context(resolver);
    final effective = auth ?? item.auth;
    final headers = <Header>[
      for (final h in item.headers)
        if (h.enabled && h.key.trim().isNotEmpty)
          (ctx.text(h.key.trim()), ctx.text(h.value)),
    ];
    var url = _url(item, ctx);
    url = _applyAuthToUrl(effective, url, ctx);
    _applyAuthToHeaders(effective, headers, ctx);
    final body = await _body(item.body, headers, ctx);

    final spec = HttpRequestSpec(
      method: ctx.text(item.method.trim()).toUpperCase(),
      url: _parse(url),
      headers: headers,
      body: body,
      settings: _settings(item.settings),
    );
    return PreparedRequest(
      spec: spec,
      unresolved: ctx.unresolved,
      secretNames: ctx.secretNames,
      masker: Masker(
        secretValues: ctx.secretValues(),
        sensitiveHeaders: [
          if (effective is ApiKeyAuth &&
              effective.addTo == ApiKeyLocation.header)
            ctx.text(effective.key),
        ],
      ),
      warnings: [
        if (effective is OAuth2Auth)
          'OAuth 2.0 needs a token first; none was added.',
        if (effective is RawAuth)
          'Auth type "${effective.type}" is not supported yet; no credentials were added.',
      ],
    );
  }

  String _url(HttpRequestItem item, _Context ctx) {
    var url = ctx.text(item.url.trim());
    final values = {
      for (final v in item.pathVars)
        if (v.enabled) ctx.text(v.key): ctx.text(v.value),
    };
    url = UrlText.applyPathVariables(url, values);
    if (url.isEmpty) throw const RequestBuildError('The URL is empty');
    return url.contains('://') ? url : 'http://$url';
  }

  Uri _parse(String url) {
    try {
      final uri = Uri.parse(url);
      if (uri.host.isEmpty) throw FormatException('missing host', url);
      return uri;
    } on FormatException catch (e) {
      throw RequestBuildError('Invalid URL "$url": ${e.message}');
    }
  }

  String _applyAuthToUrl(Auth auth, String url, _Context ctx) {
    if (auth is! ApiKeyAuth || auth.addTo != ApiKeyLocation.query) return url;
    final (base, query, fragment) = UrlText.split(url);
    final pair =
        '${Uri.encodeQueryComponent(ctx.text(auth.key))}='
        '${Uri.encodeQueryComponent(ctx.text(auth.value))}';
    final joined = query == null || query.isEmpty ? pair : '$query&$pair';
    return '$base?$joined${fragment == null ? '' : '#$fragment'}';
  }

  void _applyAuthToHeaders(Auth auth, List<Header> headers, _Context ctx) {
    final (String, String)? added = switch (auth) {
      BearerAuth(:final token) => (
        'Authorization',
        'Bearer ${ctx.text(token)}',
      ),
      BasicAuth(:final username, :final password) => (
        'Authorization',
        'Basic ${base64Encode(utf8.encode('${ctx.text(username)}:${ctx.text(password)}'))}',
      ),
      ApiKeyAuth(:final key, :final value, :final addTo)
          when addTo == ApiKeyLocation.header =>
        (ctx.text(key), ctx.text(value)),
      _ => null,
    };
    // An explicit header from the user wins over generated auth.
    if (added != null && !_has(headers, added.$1)) headers.add(added);
  }

  Future<List<int>?> _body(
    RequestBody body,
    List<Header> headers,
    _Context ctx,
  ) async {
    switch (body) {
      case NoBody():
        return null;
      case RawBody(:final text):
        _defaultContentType(headers, body.defaultContentType);
        return utf8.encode(ctx.text(text));
      case UrlEncodedBody(:final fields):
        _defaultContentType(headers, body.defaultContentType);
        return utf8.encode(_urlEncode(fields, ctx));
      case FormDataBody(:final fields):
        return _multipart(fields, headers, ctx);
      case BinaryBody(:final attachmentId):
        _defaultContentType(headers, body.defaultContentType);
        if (attachmentId == null) return null;
        return _read(attachmentId);
    }
  }

  String _urlEncode(List<KeyValue> fields, _Context ctx) => [
    for (final f in fields)
      if (f.enabled && f.key.isNotEmpty)
        '${Uri.encodeQueryComponent(ctx.text(f.key))}='
            '${Uri.encodeQueryComponent(ctx.text(f.value))}',
  ].join('&');

  Future<List<int>> _multipart(
    List<KeyValue> fields,
    List<Header> headers,
    _Context ctx,
  ) async {
    final boundary = '----PostItBoundary${_hex(16)}';
    final out = BytesBuilder();
    for (final f in fields) {
      if (!f.enabled || f.key.isEmpty) continue;
      final name = _quote(ctx.text(f.key));
      out.add(utf8.encode('--$boundary\r\n'));
      if (f.type == KeyValueType.file) {
        final ref = ctx.text(f.value);
        final filename = _quote(ref.split(RegExp(r'[\\/]')).last);
        out.add(
          utf8.encode(
            'Content-Disposition: form-data; name="$name"; filename="$filename"\r\n'
            'Content-Type: application/octet-stream\r\n\r\n',
          ),
        );
        out.add(await _read(ref));
      } else {
        out.add(
          utf8.encode(
            'Content-Disposition: form-data; name="$name"\r\n\r\n${ctx.text(f.value)}',
          ),
        );
      }
      out.add(utf8.encode('\r\n'));
    }
    out.add(utf8.encode('--$boundary--\r\n'));
    if (!_has(headers, 'Content-Type')) {
      headers.add(('Content-Type', 'multipart/form-data; boundary=$boundary'));
    }
    return out.toBytes();
  }

  Future<List<int>> _read(String reference) async {
    final reader = readFile;
    if (reader == null) {
      throw RequestBuildError(
        'Cannot read "$reference": file access is not available',
      );
    }
    try {
      return await reader(reference);
    } catch (e) {
      throw RequestBuildError('Cannot read "$reference": $e');
    }
  }

  String _quote(String s) =>
      s.replaceAll('"', '%22').replaceAll('\r', '').replaceAll('\n', '');

  String _hex(int bytes) => List.generate(
    bytes,
    (_) => _random.nextInt(256).toRadixString(16).padLeft(2, '0'),
  ).join();

  void _defaultContentType(List<Header> headers, String? type) {
    if (type != null && !_has(headers, 'Content-Type')) {
      headers.add(('Content-Type', type));
    }
  }

  bool _has(List<Header> headers, String name) {
    final lower = name.toLowerCase();
    return headers.any((h) => h.$1.toLowerCase() == lower);
  }

  HttpSettings _settings(RequestSettings s) => HttpSettings(
    timeout: s.timeoutMs == null
        ? defaults.timeout
        : Duration(milliseconds: s.timeoutMs!),
    followRedirects: s.followRedirects ?? defaults.followRedirects,
    maxRedirects: s.maxRedirects ?? defaults.maxRedirects,
    verifyTls: s.verifyTls ?? defaults.verifyTls,
    autoDecompress: s.autoDecompress ?? defaults.autoDecompress,
    keepMethodOnRedirect:
        s.keepMethodOnRedirect ?? defaults.keepMethodOnRedirect,
    stripAuthCrossOrigin:
        s.stripAuthCrossOrigin ?? defaults.stripAuthCrossOrigin,
  );
}

/// Accumulates what resolution found across all fields of one request.
class _Context {
  _Context(this.resolver);

  final VariableResolver resolver;
  final Set<String> unresolved = {};
  final Set<String> secretNames = {};

  String text(String input) {
    final r = resolver.resolve(input);
    unresolved.addAll(r.unresolved);
    secretNames.addAll(r.secretNames);
    return r.value;
  }

  List<String> secretValues() => [
    for (final name in secretNames) resolver.resolve('{{$name}}').value,
  ];
}
