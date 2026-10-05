import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:fjs/fjs.dart';

import 'package:postit_script/postit_script.dart';

export 'package:postit_script/postit_script.dart'
    show ScriptEngine, defaultScriptTimeout, scriptMemoryLimit;

final scriptEngineProvider = Provider<ScriptEngine>((ref) => FjsScriptEngine());

/// QuickJS-ng through `fjs` (ADR-002). Every run gets a fresh engine with no
/// host modules, a memory cap and a wall-clock timeout; closing the engine
/// interrupts a script that never returns.
class FjsScriptEngine implements ScriptEngine {
  static Future<void>? _init;

  @override
  Future<ScriptOutput> run(
    ScriptInput input, {
    Duration timeout = defaultScriptTimeout,
  }) async {
    final watch = Stopwatch()..start();
    JsEngine? engine;
    try {
      await (_init ??= LibFjs.init());
      engine = await JsEngine.create(
        builtins: const JsBuiltinOptions(),
        runtimeOptions: JsEngineRuntimeOptions(
          memoryLimit: BigInt.from(scriptMemoryLimit),
          maxStackSize: BigInt.from(512 * 1024),
        ),
      );
      await engine.init(
        bridge: (_) =>
            const JsResult.err(JsError.generic('Host calls are not allowed')),
      );
      final value = await engine
          .eval(source: JsCode.code(input.toSource()))
          .timeout(timeout);
      final text = value.asString;
      if (text == null) {
        return ScriptOutput.failed(
          'The script runtime returned no result',
          elapsed: watch.elapsed,
        );
      }
      return ScriptOutput.fromJson(text, elapsed: watch.elapsed);
    } on TimeoutException {
      return ScriptOutput.failed(
        'Script timed out after ${timeout.inSeconds} s',
        elapsed: watch.elapsed,
      );
    } on Object catch (e) {
      return ScriptOutput.failed(_describe(e), elapsed: watch.elapsed);
    } finally {
      try {
        await engine?.close();
      } on Object {
        // Closing an engine that already failed has nothing left to report.
      }
    }
  }

  static String _describe(Object e) {
    final text = e.toString();
    if (text.contains('MemoryLimit') ||
        text.toLowerCase().contains('out of memory')) {
      return 'Script used more than ${scriptMemoryLimit ~/ (1024 * 1024)} MB';
    }
    return text;
  }
}
