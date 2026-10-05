import 'dart:convert';
import 'dart:io';

import 'package:postit_core/postit_core.dart';
import 'package:postit_storage/postit_storage.dart';

import 'headless.dart';
import 'runner.dart';

class MockRoute {
  MockRoute({
    required this.method,
    required this.segments,
    required this.requestName,
    required this.examples,
    this.query = const {},
    this.body,
  });

  final String method;

  /// Path segments; null entries match anything (`:id`, `{{var}}`).
  final List<String?> segments;
  final String requestName;
  final List<ExampleInfo> examples;

  /// Query parameters the saved request fixes. A null value only requires the
  /// parameter to be present (the saved value was a variable or empty).
  final Map<String, String?> query;

  /// Body the saved request fixes (raw bodies only); null accepts any body.
  final String? body;

  /// Routes that pin more of the request win over looser ones.
  int get specificity => query.length + (body == null ? 0 : 1);

  String get path => '/${segments.map((s) => s ?? '*').join('/')}';

  bool matches(
    String m,
    List<String> parts, {
    Map<String, String> requestQuery = const {},
    String requestBody = '',
    bool pathOnly = false,
  }) {
    if (m != method || parts.length != segments.length) return false;
    for (var i = 0; i < parts.length; i++) {
      final s = segments[i];
      if (s != null && s != parts[i]) return false;
    }
    if (pathOnly) return true;
    for (final e in query.entries) {
      if (!requestQuery.containsKey(e.key)) return false;
      if (e.value != null && requestQuery[e.key] != e.value) return false;
    }
    final want = body;
    return want == null || _sameBody(want, requestBody);
  }

  static bool _sameBody(String want, String got) {
    try {
      return jsonEncode(jsonDecode(want)) == jsonEncode(jsonDecode(got));
    } on FormatException {
      return want.trim() == got.trim();
    }
  }
}

/// Serves the saved examples of a collection over HTTP (FR-COL-005). A
/// request's route is its method and URL path, plus the query parameters and
/// raw body it pins. The first example answers, or the one named by the
/// `X-PostIt-Example` header; `X-PostIt-Delay` (ms) slows the reply.
class MockServer {
  MockServer._(this._server, this.routes, this._delay);

  final HttpServer _server;
  final List<MockRoute> routes;
  final Duration _delay;

  /// Upper bound for the `X-PostIt-Delay` header.
  static const maxDelay = Duration(seconds: 30);

  int get port => _server.port;

  /// Routes for every request under [containerId] that has examples.
  static List<MockRoute> routesFor(
    WorkspaceRepository repo,
    String containerId, {
    String? envId,
    Map<String, String> overrides = const {},
  }) {
    final routes = <MockRoute>[];
    for (final n in requestsUnder(repo, containerId)) {
      final examples = repo.examples(n.id);
      if (examples.isEmpty) continue;
      final item = repo.getRequest(n.id);
      final resolved = VariableResolver(
        workspaceScopes(repo, n.id, envId: envId, overrides: overrides),
      );
      var url = resolved.resolve(item.url).value;
      final q = url.indexOf('?');
      final query = <String, String?>{};
      if (q >= 0) {
        for (final pair in url.substring(q + 1).split('&')) {
          if (pair.isEmpty) continue;
          final eq = pair.indexOf('=');
          final name = Uri.decodeQueryComponent(
            eq < 0 ? pair : pair.substring(0, eq),
          );
          final value = eq < 0
              ? ''
              : Uri.decodeQueryComponent(pair.substring(eq + 1));
          query[name] = value.isEmpty || value.contains('{{') ? null : value;
        }
        url = url.substring(0, q);
      }
      final body = item.body;
      final fixedBody =
          body is RawBody &&
              body.text.trim().isNotEmpty &&
              !body.text.contains('{{')
          ? body.text
          : null;
      final afterScheme = url.replaceFirst(RegExp(r'^[a-zA-Z][\w+.-]*://'), '');
      final slash = afterScheme.indexOf('/');
      final path = slash < 0 ? '' : afterScheme.substring(slash);
      routes.add(
        MockRoute(
          method: item.method.toUpperCase(),
          segments: [
            for (final s in path.split('/'))
              if (s.isNotEmpty)
                s.startsWith(':') || s.contains('{{') ? null : s,
          ],
          requestName: n.name,
          examples: examples,
          query: query,
          body: fixedBody,
        ),
      );
    }
    return routes;
  }

  static Future<MockServer> start(
    List<MockRoute> routes, {
    int port = 0,
    InternetAddress? address,
    Duration delay = Duration.zero,
  }) async {
    final server = await HttpServer.bind(
      address ?? InternetAddress.loopbackIPv4,
      port,
    );
    final mock = MockServer._(server, routes, delay);
    server.listen(mock._handle);
    return mock;
  }

  static const _skipHeaders = {
    'content-length',
    'transfer-encoding',
    'content-encoding',
    'connection',
    'keep-alive',
  };

  Future<void> _handle(HttpRequest req) async {
    final requestBody = await utf8.decodeStream(req);
    final parts = [
      for (final s in req.uri.pathSegments)
        if (s.isNotEmpty) s,
    ];
    final candidates = routes
        .where(
          (r) => r.matches(
            req.method.toUpperCase(),
            parts,
            requestQuery: req.uri.queryParameters,
            requestBody: requestBody,
          ),
        )
        .toList();
    // Stable sort: ties keep collection order.
    candidates.sort((a, b) => b.specificity.compareTo(a.specificity));
    // A request saved with a sample query or body still answers when nothing
    // pins it exactly, so a lone `?x=1` does not make the route unreachable.
    final route =
        candidates.firstOrNull ??
        (routes
                .where(
                  (r) => r.matches(
                    req.method.toUpperCase(),
                    parts,
                    pathOnly: true,
                  ),
                )
                .toList()
              ..sort((a, b) => a.specificity.compareTo(b.specificity)))
            .firstOrNull;
    final res = req.response;
    if (route == null) {
      res
        ..statusCode = 404
        ..headers.contentType = ContentType.json
        ..write(
          jsonEncode({
            'error': 'No example for ${req.method} ${req.uri.path}',
            'routes': [for (final r in routes) '${r.method} ${r.path}'],
          }),
        );
      await res.close();
      return;
    }
    final asked = int.tryParse(req.headers.value('x-postit-delay') ?? '');
    var wait = asked == null ? _delay : Duration(milliseconds: asked);
    if (wait > maxDelay) wait = maxDelay;
    if (wait > Duration.zero) await Future<void>.delayed(wait);
    final wanted = req.headers.value('x-postit-example');
    final example =
        route.examples.where((e) => e.name == wanted).firstOrNull ??
        route.examples.first;
    res.statusCode = (example.data['status'] as num?)?.toInt() ?? 200;
    for (final h in (example.data['headers'] as List?) ?? const []) {
      final pair = h as List;
      final name = '${pair[0]}';
      if (_skipHeaders.contains(name.toLowerCase())) continue;
      res.headers.add(name, '${pair[1]}');
    }
    res.contentLength = example.body.length;
    res.add(example.body);
    await res.close();
  }

  Future<void> close() => _server.close(force: true);
}
