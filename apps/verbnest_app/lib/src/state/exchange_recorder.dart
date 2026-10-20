import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:verbnest_core/verbnest_core.dart';
import 'package:verbnest_http/verbnest_http.dart';
import 'package:verbnest_runner/verbnest_runner.dart' show HistoryRecorder;

import 'console_log.dart';
import 'prefs.dart';
import 'session.dart';
import 'variables.dart';

/// Stores the exchange in the console and in local history with secrets
/// masked (FR-HIS-001). A failure to record must never break sending.
void recordExchange(
  Ref ref, {
  required String requestId,
  required HttpRequestItem item,
  required PreparedRequest prepared,
  required String? envId,
  HttpResponseRecord? response,
  String? error,
}) {
  try {
    final session = ref.read(sessionProvider);
    final prefs = ref.read(prefsProvider);
    final console = ref.read(consoleLogProvider.notifier);
    console.add(consoleEntryFor(prepared, response, error));
    final recorder = HistoryRecorder(
      local: session.local,
      workspaceId: session.repo.workspaceId,
      environmentName: envId == null
          ? null
          : session.repo
                .environments()
                .where((e) => e.id == envId)
                .firstOrNull
                ?.name,
      storeBodies: prefs.historyBodies,
      maxEntries: prefs.historyMax,
      maxAge: prefs.historyDays == 0 ? null : Duration(days: prefs.historyDays),
    );
    recorder.record(
      requestId: requestId,
      item: item,
      prepared: prepared,
      response: response,
      error: error,
    );
    if (recorder.lastError != null) {
      console.warnOnce(
        'history',
        ConsoleEntry(
          at: DateTime.now(),
          method: 'HISTORY',
          url: '',
          sentHead: '',
          error: 'History could not be saved: ${recorder.lastError}',
        ),
      );
    }
    ref.read(historyTickProvider.notifier).bump();
  } catch (_) {
    // History is best-effort.
  }
}

/// The console line for one exchange, with secrets masked.
ConsoleEntry consoleEntryFor(
  PreparedRequest p,
  HttpResponseRecord? response,
  String? error,
) {
  final spec = p.spec;
  final url = p.masker.maskText(spec.url.toString());
  return ConsoleEntry(
    at: DateTime.now(),
    method: spec.method,
    url: url,
    sentHead: response != null
        ? p.masker.maskHead(response.sent.head)
        : '${spec.method} $url',
    status: response?.status,
    ms: response?.timings.total.inMilliseconds,
    responseHead: response == null
        ? null
        : '${response.httpVersion} ${response.status} ${response.reason}\n'
              '${response.headers.map((h) => '${h.$1}: ${h.$2}').join('\n')}',
    error: error,
  );
}
