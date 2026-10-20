import 'dart:io';

import 'package:verbnest_script/verbnest_script.dart';
import 'package:test/test.dart';

ScriptInput _input(String code, {ScriptPhase phase = ScriptPhase.post}) =>
    ScriptInput(
      code: code,
      phase: phase,
      requestName: 'r',
      requestId: 'id',
      request: const {
        'method': 'GET',
        'url': 'http://x',
        'headers': [],
        'body': '',
      },
      response: const {
        'code': 200,
        'status': 'OK',
        'headers': [],
        'body': '{"a":1}',
        'time': 5,
        'size': 7,
      },
    );

void main() async {
  final hasNode = await ProcessScriptEngine.available();
  final skip = hasNode ? null : 'node is not installed';
  final engine = ProcessScriptEngine();

  test('pm.test and pm.expect results come back', () async {
    final out = await engine.run(
      _input('''
pm.test("status ok", () => pm.expect(pm.response.code).to.equal(200));
pm.test("fails", () => pm.expect(pm.response.json().a).to.equal(2));
console.log("hi");
'''),
    );
    expect(out.error, isNull);
    expect(out.tests.map((t) => '${t.name}:${t.status}'), [
      'status ok:pass',
      'fails:fail',
    ]);
    expect(out.logs.single.text, 'hi');
  }, skip: skip);

  test('variable changes and run flow are reported', () async {
    final out = await engine.run(
      _input(
        'pm.environment.set("token", "abc"); pm.execution.setNextRequest("B");',
      ),
    );
    expect(out.changes[ScriptScope.environment]!.single.key, 'token');
    expect(out.flow.next, 'B');
  }, skip: skip);

  test('a thrown error is reported, not thrown', () async {
    final out = await engine.run(_input('throw new Error("boom")'));
    expect(out.error, contains('boom'));
  }, skip: skip);

  test('an endless loop is stopped by the timeout', () async {
    final out = await engine.run(
      _input('while(true){}'),
      timeout: const Duration(milliseconds: 300),
    );
    expect(out.error, isNotNull);
  }, skip: skip);

  test('scripts cannot reach node globals', () async {
    final out = await engine.run(
      _input(
        'pm.test("t", () => pm.expect(typeof process).to.equal("undefined"));',
      ),
    );
    expect(out.tests.single.status, 'pass');
  }, skip: skip);

  test('a missing runtime is a clear error', () async {
    final out = await ProcessScriptEngine(executable: 'no-such-js-runtime')
        .run(_input('1'));
    expect(out.error, contains('no-such-js-runtime'));
  });

  sandboxTests();
}

/// A stand-in runtime that has no `--permission` flag (an old Node).
Future<String> _oldNode() async {
  final dir = await Directory.systemTemp.createTemp('oldnode');
  final marker = File('${dir.path}/ran');
  final f = File('${dir.path}/node');
  f.writeAsStringSync('''#!/bin/sh
for a in "\$@"; do
  if [ "\$a" = "--permission" ]; then exit 9; fi
  if [ "\$a" = "--version" ]; then echo v18.0.0; exit 0; fi
done
touch "${marker.path}"
printf '{"error":"ran without the permission model"}'
''');
  Process.runSync('chmod', ['+x', f.path]);
  return f.path;
}

void sandboxTests() {
  test('a runtime without the permission model does not run scripts', () async {
    final exe = await _oldNode();
    final out = await ProcessScriptEngine(executable: exe).run(_input('1'));
    expect(out.error, contains('permission model'));
    expect(out.error, contains('--unsafe-node-scripts'));
    expect(File('${File(exe).parent.path}/ran').existsSync(), isFalse);
  }, skip: Platform.isWindows ? 'needs a shell script' : null);

  test('--unsafe-node-scripts runs them on an old runtime', () async {
    final exe = await _oldNode();
    final out = await ProcessScriptEngine(
      executable: exe,
      allowUnsandboxed: true,
    ).run(_input('1'));
    expect(out.error, contains('ran without the permission model'));
    expect(File('${File(exe).parent.path}/ran').existsSync(), isTrue);
  }, skip: Platform.isWindows ? 'needs a shell script' : null);
}
