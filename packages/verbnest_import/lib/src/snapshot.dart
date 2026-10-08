import 'dart:convert';
import 'dart:typed_data';

import 'package:verbnest_core/verbnest_core.dart';
import 'package:verbnest_storage/verbnest_storage.dart';
import 'package:yaml/yaml.dart';

import 'json_util.dart';
import 'yaml_emit.dart';

/// File path (forward slashes) to content.
typedef SnapshotFiles = Map<String, List<int>>;

const snapshotVersion = 1;

String _slug(String name) {
  final s = name
      .toLowerCase()
      .replaceAll(RegExp(r'[^a-z0-9]+'), '-')
      .replaceAll(RegExp(r'^-+|-+$'), '');
  return s.isEmpty ? 'item' : (s.length > 60 ? s.substring(0, 60) : s);
}

/// A name unused in [taken]; ids make collisions stable between exports.
String _unique(String name, String id, Set<String> taken) {
  var stem = _slug(name);
  if (taken.contains(stem)) {
    final tail = id.length > 6 ? id.substring(id.length - 6) : id;
    stem = '$stem-${tail.toLowerCase()}';
  }
  taken.add(stem);
  return stem;
}

List<Map<String, Object?>> _vars(List<Variable> vars) => [
  for (final v in vars)
    {
      'key': v.key,
      'value': v.secret ? '' : v.value,
      if (v.secret) 'secret': true,
      if (!v.enabled) 'enabled': false,
      if (v.description.isNotEmpty) 'description': v.description,
    },
];

List<Variable> _readVars(Object? list) => [
  for (final e in (list as List? ?? const []))
    if (e is Map)
      Variable(
        key: '${e['key']}',
        value: '${e['value'] ?? ''}',
        secret: e['secret'] == true,
        enabled: e['enabled'] != false,
        description: '${e['description'] ?? ''}',
      ),
];

/// Writes the workspace as the YAML tree of data-model.md §1.2. The same
/// workspace always gives the same bytes. Secrets are never in the database,
/// so they are not in the snapshot.
SnapshotFiles exportSnapshot(WorkspaceRepository repo) {
  final files = <String, List<int>>{};
  void put(String path, Object? doc) =>
      files[path] = utf8.encode(emitYaml(doc));

  final envs = repo.environments();
  final collections = repo.children(null);
  put('verbnest.yaml', {
    'verbnest': snapshotVersion,
    'id': repo.workspaceId,
    'name': repo.name,
    'defaultEnvironment': repo.defaultEnvironmentId,
    'settings': repo.settings,
    'collections': [for (final c in collections) c.id],
    'environments': [for (final e in envs) e.id],
  });
  put('globals.yaml', {
    'variables': _vars(repo.variables(VariableOwner.global)),
  });

  final envNames = <String>{};
  for (final e in envs) {
    put('environments/${_unique(e.name, e.id, envNames)}.yaml', {
      'id': e.id,
      'name': e.name,
      if (e.color != null) 'color': e.color,
      'variables': _vars(e.variables),
    });
  }

  final top = <String>{};
  for (final c in collections) {
    _exportContainer(repo, c, 'collections/${_unique(c.name, c.id, top)}', put);
  }

  for (final id in repo.attachmentIds()) {
    final info = repo.attachment(id)!;
    final safe = info.name.replaceAll(RegExp(r'[^A-Za-z0-9._-]'), '_');
    files['attachments/$id--$safe'] = repo.attachmentBytes(id);
    put('attachments/$id.meta.yaml', {
      'id': id,
      'name': info.name,
      if (info.mime != null) 'mime': info.mime,
      'file': '$id--$safe',
    });
  }
  return files;
}

void _exportContainer(
  WorkspaceRepository repo,
  NodeInfo node,
  String dir,
  void Function(String, Object?) put,
) {
  final raw = repo.rawNode(node.id);
  final kids = repo.children(node.id);
  final owner = node.kind == NodeKind.collection
      ? VariableOwner.collection(node.id)
      : VariableOwner.folder(node.id);
  put(
    '$dir/${node.kind == NodeKind.collection ? '_collection' : '_folder'}.yaml',
    {
      'id': node.id,
      'name': node.name,
      'description': raw['description'],
      'auth': raw['auth'],
      'scripts': raw['scripts'],
      'extra': raw['extra'],
      'variables': _vars(repo.variables(owner)),
      'order': [for (final k in kids) k.id],
    },
  );
  final taken = <String>{};
  for (final k in kids) {
    final stem = _unique(k.name, k.id, taken);
    if (k.isContainer) {
      _exportContainer(repo, k, '$dir/$stem', put);
      continue;
    }
    final r = repo.rawNode(k.id);
    put('$dir/$stem.req.yaml', {
      'id': k.id,
      'name': k.name,
      'type': r['type'],
      'description': r['description'],
      'auth': r['auth'],
      'scripts': r['scripts'],
      'data': r['data'],
      'extra': r['extra'],
    });
    final exTaken = <String>{};
    for (final e in repo.examples(k.id)) {
      put(
        '$dir/$stem.examples/${_unique(e.name, e.id, exTaken)}.example.yaml',
        {
          'id': e.id,
          'requestId': e.requestId,
          'name': e.name,
          'data': e.data,
          'bodyBase64': base64Encode(e.body),
        },
      );
    }
  }
}

class SnapshotResult {
  SnapshotResult({
    this.collections = 0,
    this.folders = 0,
    this.requests = 0,
    this.examples = 0,
    this.environments = 0,
    List<String>? conflicts,
  }) : conflicts = conflicts ?? [];

  int collections, folders, requests, examples, environments;

  /// Items left alone because the workspace already has that id or name.
  final List<String> conflicts;
}

Map<String, Object?> _doc(List<int> bytes, String path) {
  try {
    final v = plainYaml(loadYaml(utf8.decode(bytes)));
    if (v is Map<String, Object?>) return v;
  } on Object {
    // falls through to the error below
  }
  throw FormatException('$path is not a valid snapshot file');
}

String _dirOf(String p) =>
    p.contains('/') ? p.substring(0, p.lastIndexOf('/')) : '';

/// Sorts [items] by their position in [order]; unknown ids go last, ties by [tie].
List<T> _byOrder<T>(
  Iterable<T> items,
  List<String> order,
  String Function(T) idOf,
  String Function(T) tie,
) {
  int rank(T t) {
    final i = order.indexOf(idOf(t));
    return i < 0 ? order.length : i;
  }

  return items.toList()..sort((a, b) {
    final c = rank(a).compareTo(rank(b));
    return c != 0 ? c : tie(a).compareTo(tie(b));
  });
}

List<String> _ids(Object? v) => [
  for (final o in (v as List? ?? const [])) '$o',
];

/// Reads a snapshot into [repo]. In an empty workspace the workspace id, name
/// and settings come along, so export, import, export gives identical files.
/// Otherwise items are merged by id; anything already there is kept and
/// listed in [SnapshotResult.conflicts].
SnapshotResult importSnapshot(WorkspaceRepository repo, SnapshotFiles files) =>
    _SnapshotImporter(repo, files).run();

class _SnapshotImporter {
  _SnapshotImporter(this.repo, this.files)
    : manifest = _readManifest(files),
      fresh =
          repo.children(null).isEmpty &&
          repo.environments().isEmpty &&
          repo.variables(VariableOwner.global).isEmpty;

  final WorkspaceRepository repo;
  final SnapshotFiles files;
  final Map<String, Object?> manifest;
  final bool fresh;
  final result = SnapshotResult();

  final _containers = <String, Map<String, Object?>>{};
  final _requests = <String, List<(String, Map<String, Object?>)>>{};
  final _examples = <Map<String, Object?>>[];

  static Map<String, Object?> _readManifest(SnapshotFiles files) {
    // Snapshots written before the rename to Verbnest use postit.yaml and a
    // `postit` version key.
    final legacy = files['verbnest.yaml'] == null;
    final name = legacy ? 'postit.yaml' : 'verbnest.yaml';
    final bytes = files[name];
    if (bytes == null) {
      throw const FormatException(
        'verbnest.yaml is missing: not a Verbnest snapshot',
      );
    }
    final m = _doc(bytes, name);
    if (((legacy ? m['postit'] : m['verbnest']) as int? ?? 0) >
        snapshotVersion) {
      throw const FormatException('This snapshot is from a newer Verbnest');
    }
    return m;
  }

  SnapshotResult run() {
    _workspace();
    _attachments();
    _globals();
    _environments();
    _scanCollections();
    final tops = _byOrder(
      _containers.keys.where((d) => _dirOf(d) == 'collections'),
      _ids(manifest['collections']),
      (d) => '${_containers[d]!['id']}',
      (d) => d,
    );
    for (final d in tops) {
      _restoreContainer(d, null);
    }
    _restoreExamples();
    return result;
  }

  void _workspace() {
    if (!fresh) return;
    if (manifest['id'] is String) {
      repo.restoreWorkspaceId(manifest['id'] as String);
    }
    repo.name = '${manifest['name'] ?? repo.name}';
    if (manifest['settings'] is Map) {
      repo.settings = (manifest['settings'] as Map).cast<String, Object?>();
    }
  }

  /// Attachments go first so requests can refer to them.
  void _attachments() {
    for (final e in files.entries) {
      if (!e.key.startsWith('attachments/') || !e.key.endsWith('.meta.yaml')) {
        continue;
      }
      final meta = _doc(e.value, e.key);
      final data = files['attachments/${meta['file']}'];
      if (data == null) continue;
      repo.restoreAttachment(
        '${meta['id']}',
        '${meta['name']}',
        meta['mime'] as String?,
        Uint8List.fromList(data),
      );
    }
  }

  void _globals() {
    final globals = files['globals.yaml'];
    if (globals == null) return;
    final have = repo.variables(VariableOwner.global);
    final keys = have.map((v) => v.key).toSet();
    final add = _readVars(_doc(globals, 'globals.yaml')['variables'])
        .where((v) => !keys.contains(v.key));
    if (add.isNotEmpty) {
      repo.saveVariables(VariableOwner.global, [...have, ...add]);
    }
  }

  void _environments() {
    final docs = _byOrder(
      [
        for (final e in files.entries)
          if (e.key.startsWith('environments/') && e.key.endsWith('.yaml'))
            _doc(e.value, e.key),
      ],
      _ids(manifest['environments']),
      (m) => '${m['id']}',
      (m) => '${m['name']}',
    );
    final names = repo.environments().map((e) => e.name).toSet();
    final ids = repo.environments().map((e) => e.id).toSet();
    for (final d in docs) {
      final id = '${d['id']}';
      final name = '${d['name']}';
      if (ids.contains(id) || names.contains(name)) {
        result.conflicts.add('Environment "$name" already exists');
        continue;
      }
      repo.saveEnvironment(
        Environment(
          id: id,
          name: name,
          color: d['color'] as String?,
          variables: _readVars(d['variables']),
        ),
      );
      result.environments++;
    }
    final def = manifest['defaultEnvironment'];
    if (fresh && def is String && repo.environments().any((e) => e.id == def)) {
      repo.defaultEnvironmentId = def;
    }
  }

  void _scanCollections() {
    for (final e in files.entries) {
      final p = e.key;
      if (!p.startsWith('collections/')) continue;
      if (p.endsWith('/_collection.yaml') || p.endsWith('/_folder.yaml')) {
        _containers[_dirOf(p)] = {
          ..._doc(e.value, p),
          '_collection': p.endsWith('/_collection.yaml'),
        };
      } else if (p.endsWith('.req.yaml')) {
        _requests.putIfAbsent(_dirOf(p), () => []).add((p, _doc(e.value, p)));
      } else if (p.endsWith('.example.yaml')) {
        _examples.add(_doc(e.value, p));
      }
    }
  }

  void _restoreContainer(String dir, String? parentId) {
    final c = _containers[dir]!;
    final id = '${c['id']}';
    final isCollection = c['_collection'] == true;
    final label = isCollection ? 'Collection' : 'Folder';
    if (repo.hasNode(id)) {
      result.conflicts.add('$label "${c['name']}" already exists');
    } else {
      repo.restoreNode({
        'id': id,
        'kind': isCollection ? 'collection' : 'folder',
        'type': null,
        'name': c['name'],
        'description': c['description'],
        'auth': c['auth'],
        'scripts': c['scripts'],
        'data': <String, Object?>{},
        'extra': c['extra'],
      }, parentId);
      final vars = _readVars(c['variables']);
      if (vars.isNotEmpty) {
        repo.saveVariables(
          isCollection
              ? VariableOwner.collection(id)
              : VariableOwner.folder(id),
          vars,
        );
      }
      isCollection ? result.collections++ : result.folders++;
    }

    final kids = <(String, String, void Function())>[
      for (final sub in _containers.keys.where((d) => _dirOf(d) == dir))
        ('${_containers[sub]!['id']}', sub, () => _restoreContainer(sub, id)),
      for (final (path, r)
          in _requests[dir] ?? <(String, Map<String, Object?>)>[])
        ('${r['id']}', path, () => _restoreRequest(r, id)),
    ];
    for (final k in _byOrder(
      kids,
      _ids(c['order']),
      (k) => k.$1,
      (k) => k.$2,
    )) {
      k.$3();
    }
  }

  void _restoreRequest(Map<String, Object?> r, String parentId) {
    final id = '${r['id']}';
    if (repo.hasNode(id)) {
      result.conflicts.add('Request "${r['name']}" already exists');
      return;
    }
    repo.restoreNode({
      'id': id,
      'kind': 'request',
      'type': r['type'] ?? 'http',
      'name': r['name'],
      'description': r['description'],
      'auth': r['auth'],
      'scripts': r['scripts'],
      'data': r['data'],
      'extra': r['extra'],
    }, parentId);
    result.requests++;
  }

  void _restoreExamples() {
    for (final e in _examples) {
      final rid = '${e['requestId']}';
      if (!repo.hasNode(rid)) continue;
      final id = '${e['id']}';
      if (repo.examples(rid).any((x) => x.id == id)) {
        result.conflicts.add('Example "${e['name']}" already exists');
        continue;
      }
      repo.restoreExample(
        ExampleInfo(
          id: id,
          requestId: rid,
          name: '${e['name']}',
          data: (e['data'] as Map?)?.cast<String, Object?>() ?? {},
          body: base64Decode('${e['bodyBase64'] ?? ''}'),
        ),
      );
      result.examples++;
    }
  }
}
