import 'dart:io';

import 'package:args/args.dart';
import 'package:postit_core/postit_core.dart';
import 'package:postit_http/postit_http.dart';
import 'package:postit_runner/postit_runner.dart';
import 'package:postit_storage/postit_storage.dart';

const _usage = '''
PostIt CLI

Usage: postit run <workspace.postit> [options]

Runs the requests of a collection or folder and exits 0 when every request
and test passed, 1 when something failed, 2 on a usage or file error.
Scripts (pre-request and post-response) are not run: the CLI has no
JavaScript runtime. No-code assertions do run.
''';

ArgParser _runParser() => ArgParser()
  ..addOption(
    'collection',
    abbr: 'c',
    help:
        'Collection or folder to run: name, id, or Collection/Folder path.\n'
        'Defaults to the only collection.',
  )
  ..addOption(
    'env',
    abbr: 'e',
    help: 'Environment name or id. Defaults to the workspace default.',
  )
  ..addMultiOption(
    'var',
    abbr: 'v',
    help:
        'Variable override, name=value (also POSTIT_VAR_<name> in the '
        'environment). Use it to supply secret values.',
  )
  ..addOption(
    'data',
    abbr: 'd',
    help: 'CSV or JSON data file, one row per iteration.',
  )
  ..addOption('iterations', abbr: 'n', defaultsTo: '1')
  ..addOption('delay', help: 'Milliseconds between requests.', defaultsTo: '0')
  ..addFlag('bail', help: 'Stop at the first failure.', negatable: false)
  ..addFlag(
    'insecure',
    abbr: 'k',
    help: 'Skip TLS verification.',
    negatable: false,
  )
  ..addOption(
    'reporter',
    abbr: 'r',
    allowed: ['cli', 'json', 'junit', 'html'],
    defaultsTo: 'cli',
  )
  ..addOption(
    'out',
    abbr: 'o',
    help: 'Write the report to this file instead of stdout.',
  )
  ..addFlag('help', abbr: 'h', negatable: false);

/// Runs the CLI; returns the process exit code.
Future<int> runCli(
  List<String> args, {
  required IOSink out,
  required IOSink err,
  Map<String, String>? environment,
}) async {
  if (args.isEmpty || args.first == '--help' || args.first == '-h') {
    out.writeln(_usage);
    out.writeln(_runParser().usage);
    return args.isEmpty ? 2 : 0;
  }
  if (args.first != 'run') {
    err.writeln('Unknown command "${args.first}". Try: postit run --help');
    return 2;
  }
  final ArgResults r;
  try {
    r = _runParser().parse(args.skip(1));
  } on FormatException catch (e) {
    err.writeln(e.message);
    return 2;
  }
  if (r['help'] as bool) {
    out.writeln(_usage);
    out.writeln(_runParser().usage);
    return 0;
  }
  if (r.rest.length != 1) {
    err.writeln('Expected one workspace file. Try: postit run --help');
    return 2;
  }

  final path = r.rest.single;
  final WorkspaceDatabase db;
  try {
    db = WorkspaceDatabase.open(path);
  } on StorageError catch (e) {
    err.writeln('Cannot open workspace: ${e.message}');
    return 2;
  }
  try {
    return await _run(r, WorkspaceRepository(db), out, err, environment);
  } on StorageError catch (e) {
    err.writeln(e.message);
    return 2;
  } finally {
    db.close();
  }
}

NodeInfo? _findContainer(WorkspaceRepository repo, String spec) {
  NodeInfo? byId;
  void walk(String? parent) {
    for (final n in repo.children(parent)) {
      if (!n.isContainer) continue;
      if (n.id == spec) byId = n;
      walk(n.id);
    }
  }

  walk(null);
  if (byId != null) return byId;
  NodeInfo? current;
  for (final part in spec.split('/')) {
    final next = repo
        .children(current?.id)
        .where((n) => n.isContainer && n.name == part)
        .firstOrNull;
    if (next == null) return null;
    current = next;
  }
  return current;
}

Future<int> _run(
  ArgResults r,
  WorkspaceRepository repo,
  IOSink out,
  IOSink err,
  Map<String, String>? environment,
) async {
  final spec = r['collection'] as String?;
  final NodeInfo? container;
  if (spec == null) {
    final roots = repo.children(null).where((n) => n.isContainer).toList();
    if (roots.length != 1) {
      err.writeln(
        roots.isEmpty
            ? 'The workspace has no collections.'
            : 'Several collections; pick one with --collection: '
                  '${roots.map((n) => n.name).join(', ')}',
      );
      return 2;
    }
    container = roots.single;
  } else {
    container = _findContainer(repo, spec);
    if (container == null) {
      err.writeln('No collection or folder "$spec".');
      return 2;
    }
  }

  final envSpec = r['env'] as String?;
  String? envId = repo.defaultEnvironmentId;
  if (envSpec != null) {
    envId = repo
        .environments()
        .where((e) => e.id == envSpec || e.name == envSpec)
        .firstOrNull
        ?.id;
    if (envId == null) {
      err.writeln('No environment "$envSpec".');
      return 2;
    }
  }
  final envName = envId == null
      ? null
      : repo.environments().where((e) => e.id == envId).firstOrNull?.name;

  final overrides = <String, String>{
    for (final e in (environment ?? Platform.environment).entries)
      if (e.key.startsWith('POSTIT_VAR_')) e.key.substring(11): e.value,
  };
  for (final v in r['var'] as List<String>) {
    final i = v.indexOf('=');
    if (i <= 0) {
      err.writeln('--var expects name=value, got "$v".');
      return 2;
    }
    overrides[v.substring(0, i)] = v.substring(i + 1);
  }

  var data = <DataRow>[];
  final dataPath = r['data'] as String?;
  if (dataPath != null) {
    try {
      data = parseDataFile(
        File(dataPath).readAsStringSync(),
        fileName: dataPath,
      );
    } on FormatException catch (e) {
      err.writeln('Data file: ${e.message}');
      return 2;
    } on FileSystemException catch (e) {
      err.writeln('Data file: ${e.message}');
      return 2;
    }
  }
  final iterations = int.tryParse(r['iterations'] as String);
  final delay = int.tryParse(r['delay'] as String);
  if (iterations == null || iterations < 1 || delay == null || delay < 0) {
    err.writeln('--iterations must be 1 or more and --delay 0 or more.');
    return 2;
  }

  final ids = [for (final n in requestsUnder(repo, container.id)) n.id];
  if (ids.isEmpty) {
    err.writeln('"${container.name}" has no requests.');
    return 2;
  }

  final s = repo.settings;
  const d = HttpSettings();
  final defaults = HttpSettings(
    timeout: Duration(
      milliseconds: s['timeoutMs'] as int? ?? d.timeout.inMilliseconds,
    ),
    verifyTls: (r['insecure'] as bool)
        ? false
        : (s['verifyTls'] as bool? ?? true),
    followRedirects: s['followRedirects'] as bool? ?? true,
    maxRedirects: s['maxRedirects'] as int? ?? d.maxRedirects,
    useSystemProxy: true,
  );
  final sender = HeadlessSender(
    repo: repo,
    engine: HttpEngine(cookieJar: CookieJar()),
    defaults: defaults,
    envId: envId,
    overrides: overrides,
  );
  final reporter = r['reporter'] as String;
  final live = reporter == 'cli' && r['out'] == null;
  final printed = <RunEntry>{};
  final report = await executeRun(
    config: RunConfig(
      name: container.name,
      requestIds: ids,
      iterations: iterations,
      delay: Duration(milliseconds: delay),
      stopOnFailure: r['bail'] as bool,
      data: data,
    ),
    repo: repo,
    step: sender.step,
    environment: envName,
    onProgress: live
        ? (p) {
            for (final e in p.entries) {
              if (printed.add(e)) out.writeln(_line(e, p.total > 1));
            }
          }
        : null,
  );

  if (sender.scriptsSkipped.isNotEmpty) {
    err.writeln(
      'Scripts were not run (the CLI has no JavaScript runtime) for: '
      '${sender.scriptsSkipped.join(', ')}',
    );
  }
  final text = switch (reporter) {
    'json' => report.toJsonText(),
    'junit' => report.toJUnit(),
    'html' => report.toHtml(),
    _ => live ? _summary(report) : '${_all(report)}\n${_summary(report)}',
  };
  final file = r['out'] as String?;
  if (file != null) {
    File(file).writeAsStringSync(text);
  } else {
    out.writeln(text);
  }
  return report.ok && !report.stoppedEarly ? 0 : 1;
}

String _line(RunEntry e, bool showIteration) {
  final mark = e.skipped
      ? '-'
      : e.ok
      ? 'PASS'
      : 'FAIL';
  final status = e.error != null ? 'error' : '${e.status ?? ''}';
  final out = StringBuffer(
    '${showIteration ? '[${e.iteration}] ' : ''}$mark ${e.method} ${e.name} '
    '$status ${e.timeMs} ms',
  );
  if (e.error != null) out.write('\n    ${e.error}');
  for (final t in e.tests.where((t) => t.failed)) {
    out.write('\n    x ${t.name}${t.message == null ? '' : ': ${t.message}'}');
  }
  return out.toString();
}

String _all(RunReport r) =>
    r.entries.map((e) => _line(e, r.iterations > 1)).join('\n');

String _summary(RunReport r) =>
    '\n${r.requests} requests, ${r.passedTests} tests passed, '
    '${r.failedTests} failed, ${r.errors} errors in ${r.duration.inMilliseconds} ms'
    '${r.stoppedEarly ? ' (stopped early)' : ''}';
