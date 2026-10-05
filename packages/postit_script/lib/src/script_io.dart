import 'dart:convert';

import 'package:postit_core/postit_core.dart';

import 'prelude.dart';

enum ScriptPhase { pre, post }

/// Variable scopes a script can read and write (FR-SCR-002).
enum ScriptScope { local, environment, collection, globals }

/// What a script needs to run. All values are plain JSON data.
class ScriptInput {
  const ScriptInput({
    required this.code,
    required this.phase,
    required this.requestName,
    required this.requestId,
    required this.request,
    this.response,
    this.variables = const {},
    this.environmentName,
    this.data = const {},
  });

  final String code;
  final ScriptPhase phase;
  final String requestName;
  final String requestId;

  /// `{method, url, headers: [{key, value}], body}` as it will be sent.
  final Map<String, Object?> request;

  /// `{code, status, headers: [{key, value}], body, time, size}`; post only.
  final Map<String, Object?>? response;

  /// Current values per scope.
  final Map<ScriptScope, Map<String, String>> variables;
  final String? environmentName;

  /// The current row of a collection run's data file; read only.
  final Map<String, String> data;

  Map<String, Object?> toJson() => {
    'data': data,
    'phase': phase.name,
    'requestName': requestName,
    'requestId': requestId,
    'request': request,
    'response': response,
    'environmentName': environmentName,
    'variables': {
      for (final s in ScriptScope.values) s.name: variables[s] ?? const {},
    },
  };

  /// The complete program for the JS engine: the `pm` runtime, then the user
  /// code, ending with a JSON string describing what happened.
  String toSource() =>
      '$scriptPrelude\n'
      '__run(${jsonEncode(jsonEncode(toJson()))}, ${jsonEncode(code)});';
}

class ConsoleLine {
  const ConsoleLine(this.level, this.text);

  final String level;
  final String text;
}

/// A variable change: a null [value] removes the variable.
class VariableChange {
  const VariableChange(this.key, this.value);

  final String key;
  final String? value;
}

/// Run flow control requested through `pm.execution` (FR-RUN-001).
class ScriptFlow {
  const ScriptFlow({this.next, this.stop = false, this.skip = false});

  /// Name of the request to run next, or null for the natural order.
  final String? next;
  final bool stop;
  final bool skip;

  bool get isDefault => next == null && !stop && !skip;
}

class ScriptOutput {
  const ScriptOutput({
    this.flow = const ScriptFlow(),
    this.tests = const [],
    this.logs = const [],
    this.changes = const {},
    this.request,
    this.error,
    this.elapsed = Duration.zero,
  });

  final ScriptFlow flow;
  final List<TestResult> tests;
  final List<ConsoleLine> logs;
  final Map<ScriptScope, List<VariableChange>> changes;

  /// The request after a pre-request script ran, same shape as the input.
  final Map<String, Object?>? request;

  /// Set when the script threw, timed out or used an unsupported API.
  final String? error;
  final Duration elapsed;

  bool get ok => error == null;

  ScriptOutput withError(String message, {Duration? elapsed}) => ScriptOutput(
    flow: flow,
    tests: tests,
    logs: logs,
    changes: changes,
    request: request,
    error: message,
    elapsed: elapsed ?? this.elapsed,
  );

  factory ScriptOutput.failed(String message, {Duration? elapsed}) =>
      ScriptOutput(error: message, elapsed: elapsed ?? Duration.zero);

  factory ScriptOutput.fromJson(String text, {required Duration elapsed}) {
    final j = jsonDecode(text) as Map<String, Object?>;
    final vars = (j['changes'] as Map?)?.cast<String, Object?>() ?? const {};
    final f = (j['flow'] as Map?)?.cast<String, Object?>();
    return ScriptOutput(
      flow: f == null
          ? const ScriptFlow()
          : ScriptFlow(
              next: f['next'] as String?,
              stop: f['stop'] as bool? ?? false,
              skip: f['skip'] as bool? ?? false,
            ),
      tests: [
        for (final t in (j['tests'] as List? ?? const []))
          TestResult.fromJson((t as Map).cast<String, Object?>()),
      ],
      logs: [
        for (final l in (j['logs'] as List? ?? const []))
          ConsoleLine(
            (l as Map)['level'] as String? ?? 'log',
            l['text'] as String? ?? '',
          ),
      ],
      changes: {
        for (final s in ScriptScope.values)
          if (vars[s.name] is Map)
            s: [
              for (final e in (vars[s.name] as Map).entries)
                VariableChange(e.key as String, e.value as String?),
            ],
      },
      request: (j['request'] as Map?)?.cast<String, Object?>(),
      error: j['error'] as String?,
      elapsed: elapsed,
    );
  }
}
