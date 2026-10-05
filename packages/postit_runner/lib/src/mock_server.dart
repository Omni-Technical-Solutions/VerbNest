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
  });

  final String method;

  /// Path segments; null entries match anything (`:id`, `{{var}}`).
  final List<String?> segments;
  final String requestName;
  final List<ExampleInfo> examples;

  String get path => '/${segments.map((s) => s ?? '*').join('/')}';

  bool matches(String m, List<String> parts) {
    if (m != method || parts.length != segments.length) return false;
    for (var i = 0; i < parts.length; i++) {
      final s = segments[i];
      if (s != null && s != parts[i]) return false;
    }
    return true;
  }
}

/// Serves the saved examples of a collection over HTTP (FR-COL-005). A
/// request's route is its method and URL path; the first example answers,
/// or the one named by the `X-PostIt-Example` header.
class MockServer {
  MockServer._(this._server, this.routes);

  final HttpServer _server;
  final List<MockRoute> routes;

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
      if (q >= 0) url = url.substring(0, q);
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
        ),
      );
    }
    return routes;
  }

  static Future<MockServer> start(
    List<MockRoute> routes, {
    int port = 0,
    InternetAddress? address,
  }) async {
    final server = await HttpServer.bind(
      address ?? InternetAddress.loopbackIPv4,
      port,
    );
    final mock = MockServer._(server, routes);
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
    await req.drain<void>();
    final parts = [
      for (final s in req.uri.pathSegments)
        if (s.isNotEmpty) s,
    ];
    final route = routes
        .where((r) => r.matches(req.method.toUpperCase(), parts))
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
