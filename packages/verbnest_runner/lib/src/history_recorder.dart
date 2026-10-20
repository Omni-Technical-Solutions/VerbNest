import 'dart:convert';

import 'package:verbnest_core/verbnest_core.dart';
import 'package:verbnest_http/verbnest_http.dart';
import 'package:verbnest_storage/verbnest_storage.dart';

/// Writes one history row per request a run sends, in the same shape the app
/// uses, so the app's history page can read rows the CLI recorded. Secrets are
/// masked before anything is stored. Best-effort: a failed write never fails
/// the run.
class HistoryRecorder {
  HistoryRecorder({
    required this.local,
    required this.workspaceId,
    this.environmentName,
    this.storeBodies = true,
    this.maxEntries = 1000,
    this.maxAge,
  });

  final LocalStore local;
  final String workspaceId;
  final String? environmentName;
  final bool storeBodies;
  final int maxEntries;
  final Duration? maxAge;

  /// Number of rows written by this recorder.
  int recorded = 0;

  /// How many writes failed, and the last failure. History is best-effort and
  /// a failure never stops a request, but it must not be invisible either.
  int failed = 0;
  Object? lastError;

  void record({
    required String requestId,
    required HttpRequestItem item,
    PreparedRequest? prepared,
    HttpResponseRecord? response,
    String? error,
  }) {
    try {
      final masker = prepared?.masker;
      String mask(String s) => masker?.maskText(s) ?? s;
      final spec = prepared?.spec;
      final url = mask(spec?.url.toString() ?? item.url);
      local.addHistory(
        HistoryEntry(
          id: Ulid.generate(),
          workspaceId: workspaceId,
          requestId: requestId,
          method: spec?.method ?? item.method,
          url: url,
          environmentName: environmentName,
          sentAt: DateTime.now(),
          status: response?.status,
          totalMs: response?.timings.total.inMilliseconds,
          requestJson: jsonEncode({
            'method': spec?.method ?? item.method,
            'url': url,
            'headers': [
              if (spec != null)
                for (final (k, v) in spec.headers)
                  [k, masker?.headerValue(k, v) ?? v],
            ],
            'body': spec?.body == null || !storeBodies
                ? null
                : mask(utf8.decode(spec!.body!, allowMalformed: true)),
          }),
          responseMetaJson: response == null
              ? null
              : jsonEncode({
                  'reason': response.reason,
                  'headers': [
                    for (final (k, v) in response.headers) [k, v],
                  ],
                }),
          responseBody: response?.body,
          error: error,
        ),
        storeBodies: storeBodies,
      );
      recorded++;
      local.pruneHistory(workspaceId, maxEntries: maxEntries, maxAge: maxAge);
    } catch (e) {
      // Best-effort: the request goes on, but the caller can report this.
      failed++;
      lastError = e;
    }
  }
}
