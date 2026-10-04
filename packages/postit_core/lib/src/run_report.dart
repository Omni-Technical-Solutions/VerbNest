import 'dart:convert';

import 'test_result.dart';

/// One request in one iteration of a run.
class RunEntry {
  const RunEntry({
    required this.iteration,
    required this.requestId,
    required this.name,
    required this.method,
    required this.url,
    this.status,
    this.reason = '',
    this.timeMs = 0,
    this.tests = const [],
    this.error,
    this.skipped = false,
  });

  /// 1-based.
  final int iteration;
  final String requestId;
  final String name;
  final String method;
  final String url;
  final int? status;
  final String reason;
  final int timeMs;
  final List<TestResult> tests;

  /// Network error, script error or build error; null when the request ran.
  final String? error;
  final bool skipped;

  int get failedTests => tests.where((t) => t.failed).length;
  int get passedTests => tests.where((t) => t.passed).length;
  bool get ok => !skipped && error == null && failedTests == 0;

  Map<String, Object?> toJson() => {
    'iteration': iteration,
    'requestId': requestId,
    'name': name,
    'method': method,
    'url': url,
    if (status != null) 'status': status,
    if (reason.isNotEmpty) 'reason': reason,
    'timeMs': timeMs,
    'tests': [for (final t in tests) t.toJson()],
    if (error != null) 'error': error,
    if (skipped) 'skipped': true,
  };

  factory RunEntry.fromJson(Map<String, Object?> j) => RunEntry(
    iteration: j['iteration'] as int? ?? 1,
    requestId: j['requestId'] as String? ?? '',
    name: j['name'] as String? ?? '',
    method: j['method'] as String? ?? '',
    url: j['url'] as String? ?? '',
    status: j['status'] as int?,
    reason: j['reason'] as String? ?? '',
    timeMs: j['timeMs'] as int? ?? 0,
    tests: [
      for (final t in (j['tests'] as List? ?? const []))
        TestResult.fromJson((t as Map).cast<String, Object?>()),
    ],
    error: j['error'] as String?,
    skipped: j['skipped'] as bool? ?? false,
  );
}

/// The outcome of a collection run, exportable as JSON, JUnit XML or HTML
/// (FR-RUN-003).
class RunReport {
  const RunReport({
    required this.name,
    required this.startedAt,
    required this.finishedAt,
    required this.iterations,
    this.environment,
    this.entries = const [],
    this.stoppedEarly = false,
  });

  final String name;
  final DateTime startedAt;
  final DateTime finishedAt;
  final String? environment;
  final int iterations;
  final List<RunEntry> entries;

  /// Stopped on a failure or cancelled by the user.
  final bool stoppedEarly;

  Duration get duration => finishedAt.difference(startedAt);
  int get requests => entries.where((e) => !e.skipped).length;
  int get skipped => entries.where((e) => e.skipped).length;
  int get passedTests => entries.fold(0, (n, e) => n + e.passedTests);
  int get failedTests => entries.fold(0, (n, e) => n + e.failedTests);
  int get errors => entries.where((e) => e.error != null).length;
  bool get ok => entries.every((e) => e.skipped || e.ok);

  Map<String, Object?> toJson() => {
    'name': name,
    'startedAt': startedAt.toUtc().toIso8601String(),
    'finishedAt': finishedAt.toUtc().toIso8601String(),
    if (environment != null) 'environment': environment,
    'iterations': iterations,
    'stoppedEarly': stoppedEarly,
    'summary': {
      'requests': requests,
      'skipped': skipped,
      'passedTests': passedTests,
      'failedTests': failedTests,
      'errors': errors,
      'durationMs': duration.inMilliseconds,
    },
    'results': [for (final e in entries) e.toJson()],
  };

  factory RunReport.fromJson(Map<String, Object?> j) => RunReport(
    name: j['name'] as String? ?? '',
    startedAt: DateTime.parse(j['startedAt'] as String),
    finishedAt: DateTime.parse(j['finishedAt'] as String),
    environment: j['environment'] as String?,
    iterations: j['iterations'] as int? ?? 1,
    stoppedEarly: j['stoppedEarly'] as bool? ?? false,
    entries: [
      for (final e in (j['results'] as List? ?? const []))
        RunEntry.fromJson((e as Map).cast<String, Object?>()),
    ],
  );

  String toJsonText() => const JsonEncoder.withIndent('  ').convert(toJson());

  /// JUnit XML: one `testsuite` per iteration, one `testcase` per test. A
  /// request with a network or script error gets an `error` case; a request
  /// without tests gets one case that passes when the request ran.
  String toJUnit() {
    final b = StringBuffer('<?xml version="1.0" encoding="UTF-8"?>\n');
    var allTests = 0, allFailures = 0, allErrors = 0, allSkipped = 0;
    final suites = StringBuffer();
    for (var i = 1; i <= iterations; i++) {
      final inIteration = entries.where((e) => e.iteration == i).toList();
      if (inIteration.isEmpty) continue;
      final cases = StringBuffer();
      var tests = 0, failures = 0, errors = 0, skipped = 0;
      var time = 0;
      for (final e in inIteration) {
        time += e.timeMs;
        final cls = _xml('${e.method} ${e.name}');
        final seconds = (e.timeMs / 1000).toStringAsFixed(3);
        if (e.skipped) {
          tests++;
          skipped++;
          cases.writeln(
            '    <testcase classname="$cls" name="request" time="0.000"><skipped/></testcase>',
          );
          continue;
        }
        if (e.error != null) {
          tests++;
          errors++;
          cases.writeln(
            '    <testcase classname="$cls" name="request" time="$seconds">'
            '<error message="${_xml(e.error!)}"/></testcase>',
          );
        } else if (e.tests.isEmpty) {
          tests++;
          cases.writeln(
            '    <testcase classname="$cls" name="request" time="$seconds"/>',
          );
        }
        for (final t in e.tests) {
          tests++;
          final name = _xml(t.name);
          if (t.failed) {
            failures++;
            cases.writeln(
              '    <testcase classname="$cls" name="$name" time="0.000">'
              '<failure message="${_xml(t.message ?? 'failed')}"/></testcase>',
            );
          } else if (t.skipped) {
            skipped++;
            cases.writeln(
              '    <testcase classname="$cls" name="$name" time="0.000"><skipped/></testcase>',
            );
          } else {
            cases.writeln(
              '    <testcase classname="$cls" name="$name" time="0.000"/>',
            );
          }
        }
      }
      allTests += tests;
      allFailures += failures;
      allErrors += errors;
      allSkipped += skipped;
      suites.writeln(
        '  <testsuite name="${_xml('$name - iteration $i')}" tests="$tests" '
        'failures="$failures" errors="$errors" skipped="$skipped" '
        'time="${(time / 1000).toStringAsFixed(3)}" '
        'timestamp="${startedAt.toUtc().toIso8601String()}">',
      );
      suites.write(cases);
      suites.writeln('  </testsuite>');
    }
    b.writeln(
      '<testsuites name="${_xml(name)}" tests="$allTests" '
      'failures="$allFailures" errors="$allErrors" skipped="$allSkipped" '
      'time="${(duration.inMilliseconds / 1000).toStringAsFixed(3)}">',
    );
    b.write(suites);
    b.writeln('</testsuites>');
    return b.toString();
  }

  /// A single self-contained page.
  String toHtml() {
    final b = StringBuffer()
      ..writeln('<!doctype html><html lang="en"><head><meta charset="utf-8">')
      ..writeln('<title>${_xml(name)} - run report</title>')
      ..writeln('<style>')
      ..writeln(
        'body{font:14px system-ui,sans-serif;margin:24px;color:#222}'
        'table{border-collapse:collapse;width:100%}'
        'td,th{border-bottom:1px solid #ddd;padding:6px 8px;text-align:left;vertical-align:top}'
        '.pass{color:#1b7f3b}.fail{color:#b3261e}.skip{color:#777}'
        '.sum span{margin-right:18px}',
      )
      ..writeln('</style></head><body>')
      ..writeln('<h1>${_xml(name)}</h1>')
      ..writeln(
        '<p class="sum"><span>$requests requests</span>'
        '<span class="pass">$passedTests tests passed</span>'
        '<span class="${failedTests > 0 ? 'fail' : 'pass'}">$failedTests failed</span>'
        '<span class="${errors > 0 ? 'fail' : 'pass'}">$errors errors</span>'
        '<span>${duration.inMilliseconds} ms</span>'
        '${environment == null ? '' : '<span>Environment: ${_xml(environment!)}</span>'}'
        '${stoppedEarly ? '<span class="fail">Stopped early</span>' : ''}</p>',
      )
      ..writeln(
        '<table><tr><th>#</th><th>Request</th><th>Status</th><th>Time</th><th>Tests</th></tr>',
      );
    for (final e in entries) {
      final status = e.skipped
          ? '<span class="skip">skipped</span>'
          : e.error != null
          ? '<span class="fail">${_xml(e.error!)}</span>'
          : '${e.status ?? ''} ${_xml(e.reason)}';
      final tests = StringBuffer();
      for (final t in e.tests) {
        tests.write(
          '<div class="${t.status}">${t.passed
              ? '&#10003;'
              : t.failed
              ? '&#10007;'
              : '-'} '
          '${_xml(t.name)}${t.message == null ? '' : ' - ${_xml(t.message!)}'}</div>',
        );
      }
      b.writeln(
        '<tr><td>${e.iteration}</td><td>${_xml(e.method)} ${_xml(e.name)}'
        '<br><small>${_xml(e.url)}</small></td><td>$status</td>'
        '<td>${e.timeMs} ms</td><td>$tests</td></tr>',
      );
    }
    b.writeln('</table></body></html>');
    return b.toString();
  }
}

String _xml(String s) => s
    .replaceAll('&', '&amp;')
    .replaceAll('<', '&lt;')
    .replaceAll('>', '&gt;')
    .replaceAll('"', '&quot;')
    .replaceAll("'", '&apos;')
    .replaceAll(RegExp(r'[\x00-\x08\x0B\x0C\x0E-\x1F]'), '');
