import 'dart:io';

import 'package:postit_core/postit_core.dart';
import 'package:postit_storage/postit_storage.dart';
import 'package:sqlite3/sqlite3.dart';
import 'package:test/test.dart';

HttpRequestItem draft(String name, {String url = '/'}) =>
    HttpRequestItem(id: 'ignored', name: name, url: url);

void main() {
  late WorkspaceDatabase ws;
  late WorkspaceRepository repo;

  setUp(() {
    ws = WorkspaceDatabase.memory();
    repo = WorkspaceRepository(ws);
  });
  tearDown(() => ws.close());

  group('opening files', () {
    late Directory dir;
    setUp(() => dir = Directory.systemTemp.createTempSync('postit_ws'));
    tearDown(() => dir.deleteSync(recursive: true));

    test('creates, reopens and keeps data', () {
      final path = '${dir.path}/a.postit';
      final a = WorkspaceDatabase.open(path, create: true);
      final r = WorkspaceRepository(a)..name = 'My API';
      final col = r.createCollection('Petstore');
      a.close();

      final b = WorkspaceDatabase.open(path);
      final r2 = WorkspaceRepository(b);
      expect(r2.name, 'My API');
      expect(r2.children(null).single.id, col);
      b.close();
    });

    test('missing file is NotFound unless create', () {
      expect(
        () => WorkspaceDatabase.open('${dir.path}/none.postit'),
        throwsA(isA<NotFoundError>()),
      );
    });

    test('rejects a file that is not a database, leaving it untouched', () {
      final f = File('${dir.path}/notes.postit')
        ..writeAsStringSync('hello world' * 50);
      final before = f.readAsBytesSync();
      expect(
        () => WorkspaceDatabase.open(f.path),
        throwsA(isA<NotAWorkspaceError>()),
      );
      expect(f.readAsBytesSync(), before);
    });

    test('rejects a foreign SQLite database', () {
      final path = '${dir.path}/other.db';
      sqlite3.open(path)
        ..execute('CREATE TABLE t(x)')
        ..close();
      expect(
        () => WorkspaceDatabase.open(path),
        throwsA(isA<NotAWorkspaceError>()),
      );
    });

    test('rejects a newer schema without modifying it', () {
      final path = '${dir.path}/new.postit';
      WorkspaceDatabase.open(path, create: true).close();
      sqlite3.open(path)
        ..execute('PRAGMA user_version = 99')
        ..close();
      expect(
        () => WorkspaceDatabase.open(path),
        throwsA(
          isA<UnsupportedSchemaError>().having((e) => e.found, 'found', 99),
        ),
      );
      final check = sqlite3.open(path);
      expect(check.select('PRAGMA user_version').first.values.first, 99);
      check.close();
    });

    test('a second open is refused while the first holds the lock', () {
      final path = '${dir.path}/locked.postit';
      final first = WorkspaceDatabase.open(path, create: true);
      expect(
        () => WorkspaceDatabase.open(path),
        throwsA(isA<WorkspaceLockedError>()),
      );
      first.close();
      WorkspaceDatabase.open(path).close();
    });

    test('exportCopy produces an openable workspace', () {
      final path = '${dir.path}/src.postit';
      final src = WorkspaceDatabase.open(path, create: true);
      final r = WorkspaceRepository(src);
      r.createRequest(r.createCollection('C'), draft('R'));
      final out = '${dir.path}/copy.postit';
      src.exportCopy(out);
      expect(() => src.exportCopy(out), throwsA(isA<InvalidOperationError>()));
      src.close();

      final copy = WorkspaceDatabase.open(out);
      final cr = WorkspaceRepository(copy);
      expect(cr.children(cr.children(null).single.id).single.name, 'R');
      copy.close();
    });
  });

  group('tree', () {
    test('rules for what can contain what', () {
      final col = repo.createCollection('C');
      final folder = repo.createFolder(col, 'F');
      final req = repo.createRequest(folder, draft('R'));
      expect(
        () => repo.createFolder(req, 'x'),
        throwsA(isA<InvalidOperationError>()),
      );
      expect(
        () => repo.createRequest(col, draft('x')).toString(),
        returnsNormally,
      );
      expect(
        () => repo.move(col, folder, 0),
        throwsA(isA<InvalidOperationError>()),
      );
    });

    test('children keep insertion order and move reorders', () {
      final col = repo.createCollection('C');
      final a = repo.createRequest(col, draft('a'));
      final b = repo.createRequest(col, draft('b'));
      final c = repo.createRequest(col, draft('c'));
      expect(repo.children(col).map((n) => n.id), [a, b, c]);
      repo.move(c, col, 0);
      expect(repo.children(col).map((n) => n.id), [c, a, b]);
      repo.move(a, col, 99);
      expect(repo.children(col).map((n) => n.id), [c, b, a]);
    });

    test('move between folders and refuse cycles', () {
      final col = repo.createCollection('C');
      final f1 = repo.createFolder(col, 'f1');
      final f2 = repo.createFolder(f1, 'f2');
      final r = repo.createRequest(f2, draft('r'));
      repo.move(r, f1, 0);
      expect(repo.node(r).parentId, f1);
      expect(() => repo.move(f1, f2, 0), throwsA(isA<InvalidOperationError>()));
      expect(() => repo.move(f1, f1, 0), throwsA(isA<InvalidOperationError>()));
    });

    test('delete cascades to descendants, revisions and variables', () {
      final col = repo.createCollection('C');
      final f = repo.createFolder(col, 'f');
      final r = repo.createRequest(f, draft('r'));
      repo.saveVariables(VariableOwner.folder(f), [
        const Variable(key: 'k', value: 'v'),
      ]);
      repo.delete(col);
      expect(() => repo.node(r), throwsA(isA<NotFoundError>()));
      expect(repo.variables(VariableOwner.folder(f)), isEmpty);
      expect(ws.db.select('SELECT * FROM revision'), isEmpty);
    });

    test('duplicate deep-copies with new ids and keeps position', () {
      final col = repo.createCollection('C');
      final f = repo.createFolder(col, 'f');
      repo.createRequest(f, draft('r', url: '/x'));
      final tail = repo.createFolder(col, 'tail');
      repo.saveVariables(VariableOwner.folder(f), [
        const Variable(key: 'k', value: 'v'),
      ]);

      final copy = repo.duplicate(f);
      expect(repo.children(col).map((n) => n.id), [f, copy, tail]);
      expect(repo.node(copy).name, 'f copy');
      final copied = repo.children(copy).single;
      expect(repo.getRequest(copied.id).url, '/x');
      expect(repo.variables(VariableOwner.folder(copy)).single.key, 'k');
    });

    test('auth chain walks up to the collection', () {
      final col = repo.createCollection('C');
      final f = repo.createFolder(col, 'f');
      final r = repo.createRequest(f, draft('r'));
      repo.setContainerAuth(col, const BearerAuth(token: 'T'));
      final chain = repo.authChain(r);
      expect(chain, hasLength(2));
      expect(effectiveAuth(const InheritAuth(), chain), isA<BearerAuth>());
    });
  });

  group('requests', () {
    test('save and load round trip, including unknown keys', () {
      final col = repo.createCollection('C');
      final id = repo.createRequest(
        col,
        HttpRequestItem(
          id: 'x',
          name: 'Create',
          method: 'POST',
          url: '{{base}}/pets',
          headers: const [KeyValue(key: 'X-A', value: '1')],
          body: const RawBody(RawBodyLanguage.json, '{}'),
          auth: const BearerAuth(token: 't'),
          scripts: const Scripts(pre: 'p'),
          description: 'd',
        ),
      );
      final got = repo.getRequest(id);
      expect(got.method, 'POST');
      expect(got.headers.single.key, 'X-A');
      expect(got.auth, isA<BearerAuth>());
      expect(got.scripts.pre, 'p');
      expect(got.description, 'd');

      ws.db.execute(
        "UPDATE node SET data = json_set(data, '\$.future', json('{\"a\":1}')) WHERE id = ?",
        [id],
      );
      repo.saveRequest(repo.getRequest(id).copyWith(name: 'Renamed'));
      expect(repo.getRequest(id).toData()['future'], {'a': 1});
    });

    test('getRequest on a folder is an error', () {
      final col = repo.createCollection('C');
      expect(() => repo.getRequest(col), throwsA(isA<InvalidOperationError>()));
    });
  });

  group('revisions', () {
    test('one per real change, newest first, restorable', () {
      final col = repo.createCollection('C');
      final id = repo.createRequest(col, draft('r', url: '/1'));
      var item = repo.getRequest(id);
      repo.saveRequest(item); // no change, no revision
      repo.saveRequest(item.copyWith(url: '/2'));
      repo.saveRequest(item.copyWith(url: '/3'));
      expect(repo.revisions(id).map((r) => r.rev), [3, 2, 1]);

      repo.restoreRevision(id, 1);
      expect(repo.getRequest(id).url, '/1');
      expect(repo.revisions(id).first.rev, 4);
      expect(() => repo.revision(id, 99), throwsA(isA<NotFoundError>()));
    });

    test('capped at maxRevisions', () {
      final small = WorkspaceRepository(ws, maxRevisions: 3);
      final id = small.createRequest(small.createCollection('C'), draft('r'));
      for (var i = 0; i < 10; i++) {
        small.saveRequest(small.getRequest(id).copyWith(url: '/$i'));
      }
      final revs = small.revisions(id);
      expect(revs, hasLength(3));
      expect(small.revision(id, revs.last.rev).url, '/7');
    });
  });

  group('variables and environments', () {
    test('secret values are never written', () {
      final env = Environment(
        id: Ulid.generate(),
        name: 'dev',
        variables: const [
          Variable(key: 'url', value: 'https://x'),
          Variable(key: 'token', value: 'TOP-SECRET', secret: true),
        ],
      );
      repo.saveEnvironment(env);
      final dump = ws.db
          .select('SELECT value FROM variable')
          .map((r) => r['value']);
      expect(dump, isNot(contains('TOP-SECRET')));
      final loaded = repo.environment(env.id).variables;
      expect(loaded.last.secret, isTrue);
      expect(loaded.last.value, '');
    });

    test('environment names are unique and edits update in place', () {
      final a = Environment(id: Ulid.generate(), name: 'dev');
      repo.saveEnvironment(a);
      expect(
        () =>
            repo.saveEnvironment(Environment(id: Ulid.generate(), name: 'dev')),
        throwsA(isA<DuplicateNameError>()),
      );
      repo.saveEnvironment(a.copyWith(name: 'staging', color: '#fff'));
      expect(repo.environments().single.name, 'staging');
    });

    test('failed multi-row save rolls back completely', () {
      final env = Environment(
        id: Ulid.generate(),
        name: 'dev',
        variables: const [Variable(key: 'a', value: '1')],
      );
      repo.saveEnvironment(env);
      expect(
        () => repo.saveEnvironment(
          env.copyWith(
            name: 'changed',
            variables: const [
              Variable(key: 'x'),
              Variable(key: 'x'),
            ],
          ),
        ),
        throwsA(isA<DuplicateNameError>()),
      );
      final back = repo.environment(env.id);
      expect(back.name, 'dev');
      expect(back.variables.single.key, 'a');
    });

    test('globals and deleting the default environment', () {
      repo.saveVariables(VariableOwner.global, [
        const Variable(key: 'g', value: '1'),
      ]);
      expect(repo.variables(VariableOwner.global).single.value, '1');
      final env = Environment(id: Ulid.generate(), name: 'e');
      repo.saveEnvironment(env);
      repo.defaultEnvironmentId = env.id;
      expect(repo.defaultEnvironmentId, env.id);
      repo.deleteEnvironment(env.id);
      expect(repo.defaultEnvironmentId, isNull);
    });
  });

  group('misc', () {
    test('changes stream fires after writes', () {
      var count = 0;
      final sub = repo.changes.listen((_) => count++);
      repo.createCollection('C');
      expect(count, 1);
      sub.cancel();
    });

    test('workspace id is stable and settings round trip', () {
      expect(repo.workspaceId, repo.workspaceId);
      repo.settings = {
        'http': {'timeoutMs': 5},
      };
      expect(repo.settings['http'], {'timeoutMs': 5});
    });

    test('schema version and application id are set', () {
      expect(ws.schemaVersion, 1);
      expect(
        ws.db.select('PRAGMA application_id').first.values.first,
        0x504F5354,
      );
    });
  });
}
