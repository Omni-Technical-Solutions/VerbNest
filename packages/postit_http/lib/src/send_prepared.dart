import 'dart:convert';

import 'package:postit_core/postit_core.dart' show isPersistedQueryNotFound;

import 'auth_sign.dart';
import 'engine.dart';
import 'models.dart';
import 'request_builder.dart';

/// Sends [prepared]. With Digest auth the first request goes out without
/// credentials; a 401 carrying a Digest challenge is answered once with the
/// computed `Authorization` header (FR-AUTH-004).
Future<HttpResponseRecord> sendPrepared(
  HttpEngine engine,
  PreparedRequest prepared, {
  CancelToken? cancel,
}) async {
  final spec = prepared.spec;
  var first = await engine.send(spec, cancel: cancel);
  final fallback = prepared.persistedFallback;
  if (fallback != null &&
      isPersistedQueryNotFound(utf8.decode(first.body, allowMalformed: true))) {
    first = await engine.send(fallback, cancel: cancel);
  }
  final digest = prepared.digest;
  if (digest == null || first.status != 401) return first;
  final challenge = DigestChallenge.find(
    first.headers
        .where((h) => h.$1.toLowerCase() == 'www-authenticate')
        .map((h) => h.$2),
  );
  if (challenge == null) return first;

  final target = spec.url.hasQuery
      ? '${spec.url.path.isEmpty ? '/' : spec.url.path}?${spec.url.query}'
      : (spec.url.path.isEmpty ? '/' : spec.url.path);
  final value = digestAuthorization(
    challenge,
    digest,
    method: spec.method,
    uri: target,
    body: spec.body ?? const [],
  );
  return engine.send(
    HttpRequestSpec(
      method: spec.method,
      url: spec.url,
      headers: [
        for (final h in spec.headers)
          if (h.$1.toLowerCase() != 'authorization') h,
        ('Authorization', value),
      ],
      body: spec.body,
      settings: spec.settings,
    ),
    cancel: cancel,
  );
}
