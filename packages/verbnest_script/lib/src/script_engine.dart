import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'script_io.dart';

/// Runs one script. Replaceable in tests (the real engine needs a native
/// library or an external JavaScript runtime).
abstract class ScriptEngine {
  Future<ScriptOutput> run(
    ScriptInput input, {
    Duration timeout = defaultScriptTimeout,
  });
}

const defaultScriptTimeout = Duration(seconds: 5);

/// 64 MB, the memory cap per script run (FR-SCR-004).
const scriptMemoryLimit = 64 * 1024 * 1024;

/// Runs scripts in an external JavaScript runtime (`node` by default) for
/// the CLI, which has no embedded engine. The program from
/// [ScriptInput.toSource] is evaluated in a fresh `vm` context with no
/// globals beyond the language built-ins, with a wall-clock timeout.
/// QuickJS in the app and Node here differ in rare edge cases of the language.
class ProcessScriptEngine implements ScriptEngine {
  /// Scripts run only when the runtime has Node's permission model (so a
  /// script that escapes the `vm` context still has no files, processes or
  /// workers). [allowUnsandboxed] runs them anyway on an older Node, which is
  /// then exactly as trustworthy as the scripts.
  ProcessScriptEngine({
    this.executable = 'node',
    this.allowUnsandboxed = false,
  });

  final String executable;
  final bool allowUnsandboxed;

  static const _runner =
      "const vm=require('vm');"
      "const src=require('fs').readFileSync(0,'utf8');"
      "const ms=Number(process.argv[1]);"
      "try{process.stdout.write(String(vm.runInNewContext(src,Object.create(null),{timeout:ms})));}"
      "catch(e){process.stdout.write(JSON.stringify({error:String(e&&e.message||e)}));}";

  /// `node:vm` is not a security boundary, so where Node has the permission
  /// model the process also runs without file, child-process and worker access.
  Future<bool> _supportsPermission() => _permission[executable] ??= Process.run(
    executable,
    const ['--permission', '-e', '0'],
  ).then((r) => r.exitCode == 0).catchError((Object _) => false);

  static final _permission = <String, Future<bool>>{};

  /// Whether the runtime can be started.
  static Future<bool> available([String executable = 'node']) async {
    try {
      final r = await Process.run(executable, const ['--version']);
      return r.exitCode == 0;
    } on ProcessException {
      return false;
    }
  }

  @override
  Future<ScriptOutput> run(
    ScriptInput input, {
    Duration timeout = defaultScriptTimeout,
  }) async {
    final watch = Stopwatch()..start();
    final sandboxed = await _supportsPermission();
    if (!sandboxed && !allowUnsandboxed) {
      return ScriptOutput.failed(
        '"$executable" has no permission model (Node 20 or newer), and '
        '`node:vm` alone is not a security boundary, so the script was not '
        'run. Upgrade Node, or pass --unsafe-node-scripts for scripts you '
        'wrote or fully trust.',
        elapsed: watch.elapsed,
      );
    }
    final Process p;
    try {
      p = await Process.start(executable, [
        if (sandboxed) '--permission',
        '--max-old-space-size=${scriptMemoryLimit ~/ (1024 * 1024)}',
        '-e',
        _runner,
        '${timeout.inMilliseconds}',
      ]);
    } on ProcessException catch (e) {
      return ScriptOutput.failed(
        'Cannot start "$executable" to run scripts: ${e.message}',
        elapsed: watch.elapsed,
      );
    }
    p.stdin.add(utf8.encode(input.toSource()));
    final stdout = utf8.decodeStream(p.stdout);
    final stderr = utf8.decodeStream(p.stderr);
    unawaited(p.stdin.close().catchError((Object _) {}));
    final killer = Timer(timeout + const Duration(seconds: 2), p.kill);
    try {
      final code = await p.exitCode;
      final out = await stdout;
      if (code != 0 || out.isEmpty) {
        final err = (await stderr).trim();
        return ScriptOutput.failed(
          code == 0
              ? 'The script runtime returned no result'
              : (err.contains('heap out of memory')
                    ? 'Script used more than '
                          '${scriptMemoryLimit ~/ (1024 * 1024)} MB'
                    : 'Script runtime failed: ${err.split('\n').first}'),
          elapsed: watch.elapsed,
        );
      }
      try {
        return ScriptOutput.fromJson(out, elapsed: watch.elapsed);
      } on FormatException {
        return ScriptOutput.failed(out, elapsed: watch.elapsed);
      }
    } finally {
      killer.cancel();
    }
  }
}
