import 'dart:convert';
import 'dart:io';

import 'package:args/args.dart';
import 'package:verbnest_core/verbnest_core.dart';
import 'package:verbnest_http/verbnest_http.dart';
import 'package:verbnest_runner/verbnest_runner.dart';
import 'package:verbnest_script/verbnest_script.dart';
import 'package:verbnest_storage/verbnest_storage.dart';

import 'system_vault.dart';

const _usage = '''
VerbNest CLI

Usage: verbnest run <workspace.verbnest> [options]
       verbnest mock <workspace.verbnest> [options]
       verbnest history <workspace.verbnest> --db <history.db> [options]

Runs the requests of a collection or folder and exits 0 when every request
and test passed, 1 when something failed, 2 on a usage or file error.
Pre-request and post-response scripts are skipped and reported unless you pass
--allow-scripts, which runs them in an external JavaScript runtime (see
--js-runtime; Node 20 or newer, or --unsafe-node-scripts). Only allow scripts in workspaces you trust. Variables
scripts set last for the run only; nothing is written to the workspace file.

`verbnest mock` serves the saved examples of a collection over HTTP until
stopped (Ctrl+C). Each request answers on its method and URL path; send an
X-Verbnest-Example header to pick an example by name. A request that saves
query parameters or a raw body only answers matching calls when another
request shares its path; otherwise it answers any call on that path.
X-Verbnest-Delay (ms) or --delay slows replies.

`verbnest run --history <history.db>` records each request it sends in a
device-local history database (the same format the app uses; secrets are
masked). `verbnest history` lists, shows or clears those rows. Set
VERBNEST_HISTORY_DB to avoid repeating the path.

`verbnest run --vault` reads secret variables from the system secret store
(macOS Keychain, Linux libsecret) where the app saved them. --var and
VERBNEST_VAR_<name> still win.
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
        'Variable override, name=value (also VERBNEST_VAR_<name> in the '
        'environment). For secret values prefer the environment variable: '
        'command-line arguments show up in process lists.',
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
  ..addOption(
    'js-runtime',
    defaultsTo: 'node',
    help: 'Program that runs scripts.',
  )
  ..addFlag(
    'unsafe-node-scripts',
    help:
        'Run scripts even if Node has no permission model (older than Node 20). '
        'Only for scripts you wrote or fully trust.',
    negatable: false,
  )
  ..addFlag(
    'allow-scripts',
    help: 'Run the scripts in the workspace. Only use this on workspaces you trust.',
    negatable: false,
  )
  ..addFlag(
    'no-scripts',
    help: 'Do not run scripts (default).',
    negatable: false,
  )
  ..addOption('history', help: 'Record sent requests in this history database.')
  ..addFlag(
    'history-bodies',
    help: 'Store request and response bodies in history.',
    defaultsTo: true,
  )
  ..addFlag(
    'vault',
    help: 'Read secret variables from the system secret store.',
    negatable: false,
  )
  ..addMultiOption(
    'allow-secret-host',
    help:
        'With --vault: let secret NAME be sent to HOST (NAME=HOST; NAME or '
        'HOST may be *). Hosts approved in the app are honoured already.',
    valueHelp: 'NAME=HOST',
  )
  ..addFlag('help', abbr: 'h', negatable: false);

ArgParser _historyParser() => ArgParser()
  ..addOption('db', help: 'History database (or VERBNEST_HISTORY_DB).')
  ..addOption('query', abbr: 'q', help: 'Match method, URL or status.')
  ..addOption('limit', abbr: 'n', defaultsTo: '20')
  ..addOption('show', help: 'Print one entry by id.')
  ..addFlag(
    'clear',
    help: 'Delete this workspace\'s history.',
    negatable: false,
  )
  ..addFlag('help', abbr: 'h', negatable: false);

/// Runs the CLI; returns the process exit code.
Future<int> runCli(
  List<String> args, {
  required IOSink out,
  required IOSink err,
  Map<String, String>? environment,
  Future<void>? stop,
  void Function(int port)? onReady,
  SecretVault? vault,
}) async {
  if (args.isEmpty || args.first == '--help' || args.first == '-h') {
    out.writeln(_usage);
    out.writeln(_runParser().usage);
    return args.isEmpty ? 2 : 0;
  }
  final isMock = args.first == 'mock';
  final isHistory = args.first == 'history';
  if (args.first != 'run' && !isMock && !isHistory) {
    err.writeln('Unknown command "${args.first}". Try: verbnest run --help');
    return 2;
  }
  final ArgResults r;
  try {
    r =
        (isMock
                ? _mockParser()
                : isHistory
                ? _historyParser()
                : _runParser())
            .parse(args.skip(1));
  } on FormatException catch (e) {
    err.writeln(e.message);
    return 2;
  }
  if (r['help'] as bool) {
    out.writeln(_usage);
    out.writeln(
      (isMock
              ? _mockParser()
              : isHistory
              ? _historyParser()
              : _runParser())
          .usage,
    );
    return 0;
  }
  if (r.rest.length != 1) {
    err.writeln('Expected one workspace file. Try: verbnest run --help');
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
    final repo = WorkspaceRepository(db);
    return isMock
        ? await _mock(r, repo, out, err, environment, stop, onReady)
        : isHistory
        ? _history(r, repo, out, err, environment)
        : await _run(r, repo, out, err, environment, vault);
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

/// A bad option or input: printed to stderr, exit code 2.
class _UsageError implements Exception {
  _UsageError(this.message);

  final String message;
}

Future<int> _run(
  ArgResults r,
  WorkspaceRepository repo,
  IOSink out,
  IOSink err,
  Map<String, String>? environment,
  SecretVault? vault,
) async {
  LocalStore? historyDb;
  try {
    final container = _pickContainer(r, repo);
    final (envId, envName) = _pickEnvironment(r, repo);
    final overrides = _variableOverrides(r, environment);
    final data = _loadData(r);
    final (iterations, delay) = _loopSettings(r);
    final ids = [for (final n in requestsUnder(repo, container.id)) n.id];
    if (ids.isEmpty) throw _UsageError('"${container.name}" has no requests.');
    final defaults = _httpDefaults(r, repo, err);
    final secrets = await _openSecrets(r, repo, vault);
    HistoryRecorder? recorder;
    final historyPath = (r['history'] as String?) ?? _historyEnv(environment);
    if (historyPath != null && historyPath.isNotEmpty) {
      historyDb = _openHistory(historyPath);
      recorder = HistoryRecorder(
        local: historyDb,
        workspaceId: repo.workspaceId,
        environmentName: envName,
        storeBodies: r['history-bodies'] as bool,
      );
    }
    final sender = HeadlessSender(
      repo: repo,
      secrets: secrets,
      secretHostFlags: _secretHostFlags(r),
      history: recorder,
      engine: HttpEngine(cookieJar: CookieJar()),
      defaults: defaults,
      envId: envId,
      overrides: overrides,
      scripts: await _scriptEngine(r),
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
        'Scripts were not run (no JavaScript runtime; see --js-runtime) for: '
        '${sender.scriptsSkipped.join(', ')}',
      );
    }
    _writeReport(report, reporter, live, r['out'] as String?, out);
    return report.ok && !report.stoppedEarly ? 0 : 1;
  } on _UsageError catch (e) {
    err.writeln(e.message);
    return 2;
  } finally {
    historyDb?.close();
  }
}

/// The collection or folder to run: `--collection`, or the only one.
NodeInfo _pickContainer(ArgResults r, WorkspaceRepository repo) {
  final spec = r['collection'] as String?;
  if (spec == null) {
    final roots = repo.children(null).where((n) => n.isContainer).toList();
    if (roots.length != 1) {
      throw _UsageError(
        roots.isEmpty
            ? 'The workspace has no collections.'
            : 'Several collections; pick one with --collection: '
                  '${roots.map((n) => n.name).join(', ')}',
      );
    }
    return roots.single;
  }
  return _findContainer(repo, spec) ??
      (throw _UsageError('No collection or folder "$spec".'));
}

/// The environment to use (`--env`, else the workspace's default) and its name.
(String?, String?) _pickEnvironment(ArgResults r, WorkspaceRepository repo) {
  final envSpec = r['env'] as String?;
  var envId = repo.defaultEnvironmentId;
  if (envSpec != null) {
    envId = repo
        .environments()
        .where((e) => e.id == envSpec || e.name == envSpec)
        .firstOrNull
        ?.id;
    if (envId == null) throw _UsageError('No environment "$envSpec".');
  }
  final envName = envId == null
      ? null
      : repo.environments().where((e) => e.id == envId).firstOrNull?.name;
  return (envId, envName);
}

/// Variables from the environment (`VERBNEST_VAR_*`) and `--var name=value`.
Map<String, String> _variableOverrides(
  ArgResults r,
  Map<String, String>? environment,
) {
  // POSTIT_VAR_ is the name from before the rename to Verbnest; the new one
  // wins when both are set.
  final env = environment ?? Platform.environment;
  final overrides = <String, String>{
    for (final e in env.entries)
      if (e.key.startsWith('POSTIT_VAR_'))
        e.key.substring('POSTIT_VAR_'.length): e.value,
    for (final e in env.entries)
      if (e.key.startsWith('VERBNEST_VAR_'))
        e.key.substring('VERBNEST_VAR_'.length): e.value,
  };
  for (final v in r['var'] as List<String>) {
    final i = v.indexOf('=');
    if (i <= 0) throw _UsageError('--var expects name=value, got "$v".');
    overrides[v.substring(0, i)] = v.substring(i + 1);
  }
  return overrides;
}

List<DataRow> _loadData(ArgResults r) {
  final dataPath = r['data'] as String?;
  if (dataPath == null) return <DataRow>[];
  try {
    return parseDataFile(File(dataPath).readAsStringSync(), fileName: dataPath);
  } on FormatException catch (e) {
    throw _UsageError('Data file: ${e.message}');
  } on FileSystemException catch (e) {
    throw _UsageError('Data file: ${e.message}');
  }
}

(int, int) _loopSettings(ArgResults r) {
  final iterations = int.tryParse(r['iterations'] as String);
  final delay = int.tryParse(r['delay'] as String);
  if (iterations == null || iterations < 1 || delay == null || delay < 0) {
    throw _UsageError('--iterations must be 1 or more and --delay 0 or more.');
  }
  return (iterations, delay);
}

/// The workspace's HTTP settings, with `--insecure` applied.
HttpSettings _httpDefaults(ArgResults r, WorkspaceRepository repo, IOSink err) {
  final s = repo.settings;
  const d = HttpSettings();
  if (!(r['insecure'] as bool) && s['verifyTls'] == false) {
    err.writeln(
      'Warning: this workspace turns off TLS certificate verification.',
    );
  }
  return HttpSettings(
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
}

Future<SecretStore?> _openSecrets(
  ArgResults r,
  WorkspaceRepository repo,
  SecretVault? vault,
) async {
  if (!(r['vault'] as bool)) return null;
  try {
    return await VaultSecretStore.load(
      vault ?? SystemSecretVault(),
      repo.workspaceId,
    );
  } on UnsupportedError catch (e) {
    throw _UsageError('--vault: ${e.message}');
  }
}

LocalStore _openHistory(String path) {
  try {
    return LocalStore.open(path);
  } on Object catch (e) {
    throw _UsageError('Cannot open history database: $e');
  }
}

/// `--allow-secret-host NAME=HOST`, as a map from variable name to hosts.
Map<String, Set<String>> _secretHostFlags(ArgResults r) {
  final flags = <String, Set<String>>{};
  for (final entry in r['allow-secret-host'] as List<String>) {
    final eq = entry.indexOf('=');
    if (eq < 1 || eq == entry.length - 1) {
      throw _UsageError('--allow-secret-host expects NAME=HOST, got "$entry".');
    }
    (flags[entry.substring(0, eq)] ??= {}).add(
      entry.substring(eq + 1).toLowerCase(),
    );
  }
  return flags;
}

void _writeReport(
  RunReport report,
  String reporter,
  bool live,
  String? file,
  IOSink out,
) {
  final text = switch (reporter) {
    'json' => report.toJsonText(),
    'junit' => report.toJUnit(),
    'html' => report.toHtml(),
    _ => live ? _summary(report) : '${_all(report)}\n${_summary(report)}',
  };
  if (file != null) {
    File(file).writeAsStringSync(text);
  } else {
    out.writeln(text);
  }
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

ArgParser _mockParser() => ArgParser()
  ..addOption('collection', abbr: 'c', help: 'Collection or folder to serve.')
  ..addOption('env', abbr: 'e', help: 'Environment used to resolve URLs.')
  ..addMultiOption('var', abbr: 'v', help: 'Variable override, name=value.')
  ..addOption('port', abbr: 'p', defaultsTo: '3000')
  ..addOption(
    'delay',
    defaultsTo: '0',
    help:
        'Milliseconds to wait before every reply (X-Verbnest-Delay overrides).',
  )
  ..addFlag('help', abbr: 'h', negatable: false);

Future<int> _mock(
  ArgResults r,
  WorkspaceRepository repo,
  IOSink out,
  IOSink err,
  Map<String, String>? environment,
  Future<void>? stop,
  void Function(int port)? onReady,
) async {
  final spec = r['collection'] as String?;
  final roots = repo.children(null).where((n) => n.isContainer).toList();
  final NodeInfo? container = spec == null
      ? (roots.length == 1 ? roots.single : null)
      : _findContainer(repo, spec);
  if (container == null) {
    err.writeln(
      spec == null
          ? 'Pick a collection with --collection.'
          : 'No collection or folder "$spec".',
    );
    return 2;
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
  final overrides = <String, String>{};
  for (final v in r['var'] as List<String>) {
    final i = v.indexOf('=');
    if (i <= 0) {
      err.writeln('--var expects name=value, got "$v".');
      return 2;
    }
    overrides[v.substring(0, i)] = v.substring(i + 1);
  }
  final port = int.tryParse(r['port'] as String);
  if (port == null || port < 0 || port > 65535) {
    err.writeln('--port must be 0-65535.');
    return 2;
  }
  final delayMs = int.tryParse(r['delay'] as String);
  if (delayMs == null || delayMs < 0) {
    err.writeln('--delay must be a number of milliseconds.');
    return 2;
  }
  final routes = MockServer.routesFor(
    repo,
    container.id,
    envId: envId,
    overrides: overrides,
  );
  if (routes.isEmpty) {
    err.writeln('No request under "${container.name}" has a saved example.');
    return 2;
  }
  final MockServer server;
  try {
    server = await MockServer.start(
      routes,
      port: port,
      delay: Duration(milliseconds: delayMs),
    );
  } on SocketException catch (e) {
    err.writeln('Cannot listen on port $port: ${e.message}');
    return 2;
  }
  out.writeln(
    'Serving ${routes.length} routes on http://127.0.0.1:${server.port}',
  );
  for (final route in routes) {
    final pins = [
      if (route.query.isNotEmpty) 'query ${route.query.keys.join(', ')}',
      if (route.body != null) 'body',
    ];
    out.writeln(
      '  ${route.method} ${route.path}  (${route.requestName})'
      '${pins.isEmpty ? '' : ' [${pins.join('; ')}]'}',
    );
  }
  onReady?.call(server.port);
  await (stop ?? ProcessSignal.sigint.watch().first);
  await server.close();
  return 0;
}

Future<ScriptEngine?> _scriptEngine(ArgResults r) async {
  if (r['no-scripts'] as bool || !(r['allow-scripts'] as bool)) return null;
  final exe = r['js-runtime'] as String;
  return await ProcessScriptEngine.available(exe)
      ? ProcessScriptEngine(
          executable: exe,
          allowUnsandboxed: r['unsafe-node-scripts'] as bool,
        )
      : null;
}

int _history(
  ArgResults r,
  WorkspaceRepository repo,
  IOSink out,
  IOSink err,
  Map<String, String>? environment,
) {
  final path = (r['db'] as String?) ?? _historyEnv(environment);
  if (path == null || path.isEmpty) {
    err.writeln('Give the history database with --db or VERBNEST_HISTORY_DB.');
    return 2;
  }
  if (!File(path).existsSync()) {
    err.writeln('No history database at $path.');
    return 2;
  }
  final limit = int.tryParse(r['limit'] as String);
  if (limit == null || limit < 1) {
    err.writeln('--limit must be 1 or more.');
    return 2;
  }
  final LocalStore store;
  try {
    store = LocalStore.open(path);
  } on Object catch (e) {
    err.writeln('Cannot open history database: $e');
    return 2;
  }
  try {
    final ws = repo.workspaceId;
    if (r['clear'] as bool) {
      store.clearHistory(ws);
      out.writeln('History cleared.');
      return 0;
    }
    final show = r['show'] as String?;
    if (show != null) {
      final e = store.history(show);
      if (e == null || e.workspaceId != ws) {
        err.writeln('No history entry "$show" for this workspace.');
        return 2;
      }
      out.writeln('${e.method} ${e.url}');
      out.writeln(
        '${e.sentAt.toIso8601String()}  '
        '${e.error != null ? 'error: ${e.error}' : 'status ${e.status ?? '-'}'}'
        '${e.totalMs == null ? '' : '  ${e.totalMs} ms'}'
        '${e.environmentName == null ? '' : '  env ${e.environmentName}'}',
      );
      out.writeln('--- request');
      out.writeln(e.requestJson);
      final body = e.responseBody;
      if (body != null) {
        out.writeln('--- response${e.bodyTruncated ? ' (truncated)' : ''}');
        out.writeln(utf8.decode(body, allowMalformed: true));
      }
      return 0;
    }
    final rows = store.listHistory(
      ws,
      query: r['query'] as String?,
      limit: limit,
    );
    if (rows.isEmpty) out.writeln('No history.');
    for (final e in rows) {
      out.writeln(
        '${e.id}  ${e.sentAt.toIso8601String()}  ${e.method} ${e.url}  '
        '${e.error != null ? 'error' : e.status ?? '-'}'
        '${e.totalMs == null ? '' : '  ${e.totalMs} ms'}',
      );
    }
    return 0;
  } finally {
    store.close();
  }
}

String? _historyEnv(Map<String, String>? environment) {
  final env = environment ?? Platform.environment;
  return env['VERBNEST_HISTORY_DB'] ?? env['POSTIT_HISTORY_DB'];
}
