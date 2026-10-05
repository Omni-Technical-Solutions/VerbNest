import 'dart:convert';
import 'dart:io';

import 'package:postit_cli/postit_cli.dart';
import 'package:postit_core/postit_core.dart';
import 'package:postit_storage/postit_storage.dart';
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

void main() {
  late TestServer server;
  late Directory dir;
  late String file;

  setUp(() async {
    server = await TestServer.start();
    dir = Directory.systemTemp.createTempSync('postit_cli');
    file = '${dir.path}/w.postit';
    final db = WorkspaceDatabase.open(file, create: true);
    final repo = WorkspaceRepository(db);
    final col = repo.createCollection('API');
    repo.saveVariables(VariableOwner.collection(col), [
      Variable(key: 'base', value: server.baseUrl),
    ]);
    repo.createRequest(
      col,
      HttpRequestItem(
        id: '',
        name: 'echo',
        url: '{{base}}/echo?who={{who}}',
        assertions: const [
          Assertion(target: AssertionTarget.status, value: '200'),
        ],
      ),
    );
    final f = repo.createFolder(col, 'Bad');
    repo.createRequest(
      f,
      HttpRequestItem(
        id: '',
        name: 'missing',
        url: '{{base}}/status/500',
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

  Future<(int, String, String)> cli(List<String> args) async {
    final out = _Sink();
    final err = _Sink();
    final code = await runCli(args, out: out, err: err, environment: const {});
    return (code, '$out', '$err');
  }

  test(
    'whole collection runs variables in and exits 1 when a request fails',
    () async {
      final (code, out, _) = await cli([
        'run',
        file,
        '-c',
        'API',
        '-v',
        'who=me',
      ]);
      expect(code, 1);
      expect(out, contains('PASS GET echo 200'));
      expect(out, contains('FAIL GET missing 500'));
      expect(server.requests.first.target, contains('who=me'));
    },
  );

  test('--collection selects a folder by path; exit 1 on failure', () async {
    final (code, out, _) = await cli(['run', file, '-c', 'API/Bad']);
    expect(code, 1);
    expect(out, isNot(contains('echo')));
    expect(out, contains('1 requests'));
  });

  test('--bail stops at the first failure', () async {
    final (_, out, _) = await cli(['run', file, '--bail', '-v', 'who=a']);
    expect(out, contains('stopped early'));
  });

  test('json reporter writes a parseable report to --out', () async {
    final path = '${dir.path}/r.json';
    final (code, _, _) = await cli([
      'run',
      file,
      '-r',
      'json',
      '-o',
      path,
      '-v',
      'who=a',
    ]);
    expect(code, 1);
    final j = jsonDecode(File(path).readAsStringSync()) as Map;
    expect(j['name'], 'API');
    expect((j['results'] as List), hasLength(2));
  });

  test('usage and file errors exit 2', () async {
    expect((await cli([])).$1, 2);
    expect((await cli(['nope'])).$1, 2);
    expect((await cli(['run', '${dir.path}/absent.postit'])).$1, 2);
    expect(
      (await cli(['run', file, '-c', 'Nothing'])).$3,
      contains('No collection'),
    );
    expect((await cli(['run', file, '-v', 'bad'])).$1, 2);
    expect(
      (await cli(['run', file, '-e', 'prod'])).$3,
      contains('No environment'),
    );
  });
}
