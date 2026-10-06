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

void main() {
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
