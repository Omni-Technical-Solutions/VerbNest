import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:verbnest_cli/verbnest_cli.dart';
import 'package:verbnest_core/verbnest_core.dart';
import 'package:verbnest_storage/verbnest_storage.dart';
import 'package:test/test.dart';
import 'package:test_server/test_server.dart';

class _Sink implements IOSink {
  final buffer = StringBuffer();
  @override
  Encoding encoding = utf8;
  @override
  void write(Object? o) => buffer.write(o);
  @override
  void writeln([Object? o = '']) => buffer.writeln(o);
  @override
  void writeAll(Iterable<Object?> o, [String s = '']) => buffer.writeAll(o, s);
  @override
  void writeCharCode(int c) => buffer.writeCharCode(c);
  @override
  void add(List<int> data) => buffer.write(utf8.decode(data));
  @override
  void addError(Object e, [StackTrace? st]) {}
  @override
  Future<void> addStream(Stream<List<int>> s) async {}
  @override
  Future<void> close() async {}
  @override
  Future<void> flush() async {}
  @override
  Future<void> get done async {}
  @override
  String toString() => buffer.toString();
}

class _MemoryVault implements SecretVault {
  final data = <String, String>{};
  @override
  Future<String?> read(String key) async => data[key];
  @override
  Future<void> write(String key, String value) async => data[key] = value;
  @override
  Future<void> delete(String key) async => data.remove(key);
}

void main() {
  late TestServer server;
  late Directory dir;
  late String file;
  late String workspaceId;
  late VariableOwner owner;

  setUp(() async {
    server = await TestServer.start();
    dir = Directory.systemTemp.createTempSync('verbnest_cli_hv');
    file = '${dir.path}/w.verbnest';
    final db = WorkspaceDatabase.open(file, create: true);
    final repo = WorkspaceRepository(db);
    workspaceId = repo.workspaceId;
    final col = repo.createCollection('API');
    owner = VariableOwner.collection(col);
    repo.saveVariables(owner, [
      Variable(key: 'base', value: server.baseUrl),
      const Variable(key: 'token', value: '', secret: true),
    ]);
    repo.createRequest(
      col,
      HttpRequestItem(
        id: '',
        name: 'echo',
        url: '{{base}}/echo?t={{token}}',
        assertions: const [
          Assertion(target: AssertionTarget.status, value: '200'),
        ],
      ),
    );
    db.close();
  });

  tearDown(() async {
    await server.close();
    dir.deleteSync(recursive: true);
  });

  Future<(int, String, String)> cli(
    List<String> args, {
    SecretVault? vault,
    Map<String, String> env = const {},
  }) async {
    final out = _Sink();
    final err = _Sink();
    final code = await runCli(
      args,
      out: out,
      err: err,
      environment: env,
      vault: vault,
    );
    return (code, '$out', '$err');
  }

  group('vault', () {
    test('--vault supplies secret variables', () async {
      final vault = _MemoryVault();
      final store = await VaultSecretStore.load(vault, workspaceId);
      store.put(workspaceId, owner.kind, owner.id, 'token', 'S3CRET');
      await store.flush();
      final (code, _, _) = await cli(['run', file, '--vault'], vault: vault);
      expect(code, 0);
      expect(server.requests.single.target, contains('t=S3CRET'));
    });

    test('--var wins over the vault', () async {
      final vault = _MemoryVault();
      final store = await VaultSecretStore.load(vault, workspaceId);
      store.put(workspaceId, owner.kind, owner.id, 'token', 'S3CRET');
      await store.flush();
      await cli(['run', file, '--vault', '-v', 'token=cli'], vault: vault);
      expect(server.requests.single.target, contains('t=cli'));
    });

    test('without --vault the secret stays empty', () async {
      await cli(['run', file], vault: _MemoryVault());
      expect(server.requests.single.target, endsWith('t='));
    });

    test('an unreadable system store exits 2 with a reason', () async {
      final (code, _, err) = await cli([
        'run',
        file,
        '--vault',
      ], vault: SystemSecretVault(platform: 'windows'));
      expect(code, 2);
      expect(err, contains('--vault'));
      expect(err, contains('--var'));
    });

    test('SystemSecretVault builds the platform commands', () async {
      final calls = <List<String>>[];
      Future<ProcessResult> fake(String exe, List<String> args) async {
        calls.add([exe, ...args]);
        return ProcessResult(0, 0, 'value\n', '');
      }

      final mac = SystemSecretVault(run: fake, platform: 'macos');
      expect(await mac.read('k'), 'value');
      expect(calls.single, [
        'security',
        'find-generic-password',
        '-s',
        'flutter_secure_storage_service',
        '-a',
        'k',
        '-w',
      ]);
      final linux = SystemSecretVault(run: fake, platform: 'linux');
      await linux.read('k');
      expect(calls.last, ['secret-tool', 'lookup', 'account', 'k']);
      expect(() => mac.write('k', 'v'), throwsUnsupportedError);
    });

    test('a missing entry reads as null', () async {
      final v = SystemSecretVault(
        run: (_, _) async => ProcessResult(0, 44, '', 'not found'),
        platform: 'macos',
      );
      expect(await v.read('k'), isNull);
    });
  });

  group('history', () {
    test('run --history records masked rows and history lists them', () async {
      final db = '${dir.path}/h.db';
      final vault = _MemoryVault();
      final store = await VaultSecretStore.load(vault, workspaceId);
      store.put(workspaceId, owner.kind, owner.id, 'token', 'S3CRET');
      await store.flush();
      final (code, _, _) = await cli([
        'run',
        file,
        '--vault',
        '--history',
        db,
      ], vault: vault);
      expect(code, 0);

      final (c2, list, _) = await cli(['history', file, '--db', db]);
      expect(c2, 0);
      expect(list, contains('GET'));
      expect(list, contains('/echo'));
      expect(list, contains('200'));
      expect(list, isNot(contains('S3CRET')));

      final id = list.trim().split('  ').first;
      final (c3, shown, _) = await cli([
        'history',
        file,
        '--db',
        db,
        '--show',
        id,
      ]);
      expect(c3, 0);
      expect(shown, contains('--- request'));
      expect(shown, contains('--- response'));
      // The echo server repeats the secret in its reply; only the stored
      // request is masked, as in the app.
      expect(shown.split('--- response').first, isNot(contains('S3CRET')));

      final (c4, none, _) = await cli([
        'history',
        file,
        '--db',
        db,
        '-q',
        'nomatch',
      ]);
      expect(c4, 0);
      expect(none, contains('No history'));

      await cli(['history', file, '--db', db, '--clear']);
      expect(
        (await cli(['history', file, '--db', db])).$2,
        contains('No history'),
      );
    });

    test(
      'VERBNEST_HISTORY_DB works and --no-history-bodies drops bodies',
      () async {
        final db = '${dir.path}/e.db';
        final env = {'VERBNEST_HISTORY_DB': db};
        await cli(['run', file, '--no-history-bodies'], env: env);
        final id = (await cli([
          'history',
          file,
        ], env: env)).$2.trim().split('  ').first;
        final shown = (await cli(['history', file, '--show', id], env: env)).$2;
        expect(shown, isNot(contains('--- response')));
      },
    );

    test('a failed request is recorded with its error', () async {
      final db = '${dir.path}/f.db';
      await server.close();
      final (code, _, _) = await cli(['run', file, '--history', db]);
      expect(code, 1);
      final list = (await cli(['history', file, '--db', db])).$2;
      expect(list, contains('error'));
      server = await TestServer.start();
    });

    test('usage errors exit 2', () async {
      expect((await cli(['history', file])).$1, 2);
      expect(
        (await cli(['history', file, '--db', '${dir.path}/none.db'])).$1,
        2,
      );
      final db = '${dir.path}/u.db';
      await cli(['run', file, '--history', db]);
      expect((await cli(['history', file, '--db', db, '--show', 'zzz'])).$1, 2);
      expect((await cli(['history', file, '--db', db, '-n', '0'])).$1, 2);
    });
  });

  test('the pre-rename POSTIT_VAR_ and POSTIT_HISTORY_DB still work', () async {
    final db = '${dir.path}/legacy.db';
    await cli(
      ['run', file],
      env: {'POSTIT_VAR_token': 'old', 'POSTIT_HISTORY_DB': db},
    );
    expect(server.requests.single.target, contains('t=old'));
    expect(
      (await cli(['history', file], env: {'POSTIT_HISTORY_DB': db})).$2,
      contains('/echo'),
    );
    await cli(
      ['run', file],
      env: {'POSTIT_VAR_token': 'old', 'VERBNEST_VAR_token': 'new'},
    );
    expect(server.requests.last.target, contains('t=new'));
  });
}
