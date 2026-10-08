import 'dart:convert';
import 'dart:typed_data';

import 'package:verbnest_core/verbnest_core.dart';
import 'package:verbnest_import/verbnest_import.dart';
import 'package:verbnest_storage/verbnest_storage.dart';
import 'package:test/test.dart';
import 'package:yaml/yaml.dart';

WorkspaceRepository newRepo() =>
    WorkspaceRepository(WorkspaceDatabase.memory());

WorkspaceRepository sample() {
  final r = newRepo();
  r.name = 'My API';
  final c = r.createCollection('Pet store');
  r.setDescription(c, 'All pets');
  r.setContainerAuth(c, const BearerAuth(token: '{{token}}'));
  r.saveVariables(VariableOwner.collection(c), [
    const Variable(key: 'baseUrl', value: 'https://x.test'),
  ]);
  final f = r.createFolder(c, 'Pets & more');
  final a = r.createRequest(
    f,
    const HttpRequestItem(
      id: '',
      name: 'List pets',
      url: '{{baseUrl}}/pets?x=1',
      body: RawBody(RawBodyLanguage.json, '{"a": "multi\nline", "n": 1}'),
      headers: [KeyValue(key: 'X-A', value: 'yes')],
    ),
  );
  r.createRequest(f, const HttpRequestItem(id: '', name: 'List pets'));
  r.createRequest(c, const HttpRequestItem(id: '', name: 'Root'));
  r.setFavourite(a, true);
  r.addExample(a, '200 OK', {
    'status': 200,
    'headers': [
      ['Content-Type', 'application/json'],
    ],
  }, Uint8List.fromList(utf8.encode('{"ok":true}')));
  r.saveVariables(VariableOwner.global, [const Variable(key: 'g', value: '1')]);
  final e = Environment(
    id: 'ENV1',
    name: 'dev',
    variables: const [Variable(key: 'host', value: 'localhost')],
  );
  r.saveEnvironment(e);
  r.defaultEnvironmentId = 'ENV1';
  r.settings = {'timeoutMs': 5000};
  r.addAttachment('a b.txt', Uint8List.fromList([1, 2, 3]), mime: 'text/plain');
  return r;
}

void _redactionTests() {
  test('snapshot export blanks literal auth, keeps variable references', () {
    final r = WorkspaceRepository(WorkspaceDatabase.memory());
    final col = r.createCollection('c');
    r.createRequest(
      col,
      HttpRequestItem(
        id: '',
        name: 'r',
        url: 'http://x',
        auth: const BearerAuth(token: 'literal-secret'),
      ),
    );
    r.createRequest(
      col,
      HttpRequestItem(
        id: '',
        name: 'r2',
        url: 'http://x',
        auth: const BasicAuth(username: 'u', password: '{{pw}}'),
      ),
    );
    final files = exportSnapshot(r);
    final text = files.entries
        .where((e) => e.key.endsWith('.req.yaml'))
        .map((e) => utf8.decode(e.value))
        .join('\n');
    expect(text, isNot(contains('literal-secret')));
    expect(text, contains('token: ""'));
    expect(text, contains('{{pw}}'));
  });

  test('redactAuth covers each auth type', () {
    expect(
      (redactAuth(const BearerAuth(token: 't').toJson()) as Map)['token'],
      '',
    );
    final o = redactAuth(
      const OAuth2Auth(
        grant: OAuth2Grant.clientCredentials,
        tokenUrl: 'http://a',
        clientId: 'id',
        clientSecret: 'cs',
      ).toJson(),
    ) as Map;
    expect(o['clientSecret'], '');
    expect(o['clientId'], 'id');
    expect(
      (redactAuth(const AwsV4Auth(accessKey: 'ak', secretKey: 'sk').toJson())
          as Map)['secretKey'],
      '',
    );
    expect(redactAuth(null), isNull);
  });

  test('snapshot import ignores TLS and proxy settings', () {
    final r = sample();
    final files = exportSnapshot(r);
    // Smuggle hostile settings into the manifest.
    final mk = files.keys.singleWhere((k) => k.endsWith('verbnest.yaml'));
    files[mk] = utf8.encode(
      utf8
          .decode(files[mk]!)
          .replaceFirst(
            'settings:',
            'settings:\n  verifyTls: false\n  proxyHost: evil.test',
          ),
    );
    final copy = WorkspaceRepository(WorkspaceDatabase.memory());
    importSnapshot(copy, files);
    expect(copy.settings['verifyTls'], isNull);
    expect(copy.settings['proxyHost'], isNull);
    expect(copy.settings['timeoutMs'], 5000);
  });
}

void main() {
  _redactionTests();
  test('emitter output is valid YAML and round trips values', () {
    final doc = {
      'plain': 'hello world',
      'num_like': '123',
      'bool_like': 'true',
      'multi': 'a\nb "q"',
      'empty': '',
      'list': [
        {'k': 1, 'z': null},
        'x',
        [],
        {},
      ],
      'nested': {'b': false, 'a': 1.5},
    };
    final text = emitYaml(doc);
    expect(text.indexOf('bool_like'), lessThan(text.indexOf('plain')));
    final back = loadYaml(text) as YamlMap;
    expect(back['num_like'], '123');
    expect(back['bool_like'], 'true');
    expect(back['multi'], 'a\nb "q"');
    expect(back['empty'], '');
    expect((back['list'] as YamlList)[0]['z'], isNull);
    expect(back['nested']['a'], 1.5);
  });

  test('export is deterministic and has the documented layout', () {
    final repo = sample();
    final a = exportSnapshot(repo);
    final b = exportSnapshot(repo);
    expect(a.keys.toList(), b.keys.toList());
    for (final k in a.keys) {
      expect(a[k], b[k], reason: k);
    }
    expect(
      a.keys.where((k) => !k.startsWith('attachments/')),
      containsAll([
        'verbnest.yaml',
        'globals.yaml',
        'environments/dev.yaml',
        'collections/pet-store/_collection.yaml',
        'collections/pet-store/pets-more/_folder.yaml',
        'collections/pet-store/pets-more/list-pets.req.yaml',
        'collections/pet-store/root.req.yaml',
      ]),
    );
    // Same name twice: the second gets an id suffix.
    expect(
      a.keys.where((k) => k.contains('list-pets') && k.endsWith('.req.yaml')),
      hasLength(2),
    );
    expect(
      a.keys.any((k) => k.endsWith('.example.yaml') && k.contains('200-ok')),
      isTrue,
    );
  });

  test('export, import, export gives identical files', () {
    final first = exportSnapshot(sample());
    final copy = newRepo();
    final r = importSnapshot(copy, first);
    expect(r.conflicts, isEmpty);
    expect(r.collections, 1);
    expect(r.folders, 1);
    expect(r.requests, 3);
    expect(r.examples, 1);
    expect(r.environments, 1);
    final second = exportSnapshot(copy);
    expect(second.keys.toList(), first.keys.toList());
    for (final k in first.keys) {
      expect(
        utf8.decode(second[k]!, allowMalformed: true),
        utf8.decode(first[k]!, allowMalformed: true),
        reason: k,
      );
    }
    expect(copy.name, 'My API');
    expect(copy.defaultEnvironmentId, 'ENV1');
    expect(copy.settings['timeoutMs'], 5000);
    final req = copy.favourites().single;
    expect(copy.getRequest(req).body, isA<RawBody>());
    expect(
      (copy.getRequest(req).body as RawBody).text,
      contains('multi\nline'),
    );
  });

  test('merging by id keeps what is there and lists conflicts', () {
    final src = sample();
    final files = exportSnapshot(src);
    final target = newRepo();
    final c = target.createCollection('Mine');
    expect(importSnapshot(target, files).conflicts, isEmpty);
    expect(target.children(null).map((n) => n.name), ['Mine', 'Pet store']);
    expect(target.workspaceId, isNot(src.workspaceId));
    expect(c, isNotEmpty);

    final again = importSnapshot(target, files);
    expect(again.requests, 0);
    expect(
      again.conflicts,
      containsAll([
        'Collection "Pet store" already exists',
        'Environment "dev" already exists',
        'Example "200 OK" already exists',
      ]),
    );
    expect(target.children(null), hasLength(2));
  });

  test('a new request in an existing folder is merged in', () {
    final src = sample();
    final files = exportSnapshot(src);
    final target = newRepo();
    importSnapshot(target, files);
    final folder = src
        .children(src.children(null).first.id)
        .firstWhere((n) => n.isContainer);
    src.createRequest(folder.id, const HttpRequestItem(id: '', name: 'Added'));
    final r = importSnapshot(target, exportSnapshot(src));
    expect(r.requests, 1);
    expect(target.children(folder.id).map((n) => n.name), contains('Added'));
  });

  test('bad input is rejected', () {
    expect(() => importSnapshot(newRepo(), {}), throwsFormatException);
    expect(
      () => importSnapshot(newRepo(), {
        'verbnest.yaml': utf8.encode('verbnest: 99'),
      }),
      throwsFormatException,
    );
  });

  test('snapshots written before the rename (postit.yaml) still import', () {
    final files = Map<String, List<int>>.of(exportSnapshot(sample()));
    final manifest = utf8
        .decode(files.remove('verbnest.yaml')!)
        .replaceFirst('verbnest:', 'postit:');
    files['postit.yaml'] = utf8.encode(manifest);
    final target = newRepo();
    expect(importSnapshot(target, files).conflicts, isEmpty);
    expect(target.children(null).map((n) => n.name), ['Pet store']);
  });
}
