import 'dart:convert';
import 'dart:typed_data';

import 'package:postit_core/postit_core.dart';
import 'package:postit_storage/postit_storage.dart';
import 'package:yaml/yaml.dart';

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
  put('postit.yaml', {
    'postit': snapshotVersion,
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

Object? _plain(Object? v) => switch (v) {
  YamlMap() => {for (final e in v.entries) '${e.key}': _plain(e.value)},
  YamlList() => [for (final e in v) _plain(e)],
  _ => v,
};

Map<String, Object?> _doc(List<int> bytes, String path) {
  try {
    final v = _plain(loadYaml(utf8.decode(bytes)));
    if (v is Map<String, Object?>) return v;
  } on Object {
    // falls through to the error below
  }
  throw FormatException('$path is not a valid snapshot file');
}

String _dirOf(String p) =>
    p.contains('/') ? p.substring(0, p.lastIndexOf('/')) : '';

/// Reads a snapshot into [repo]. In an empty workspace the workspace id, name
/// and settings come along, so export, import, export gives identical files.
/// Otherwise items are merged by id; anything already there is kept and
/// listed in [SnapshotResult.conflicts].
SnapshotResult importSnapshot(WorkspaceRepository repo, SnapshotFiles files) {
  final manifestBytes = files['postit.yaml'];
  if (manifestBytes == null) {
    throw const FormatException(
      'postit.yaml is missing: not a PostIt snapshot',
    );
  }
  final manifest = _doc(manifestBytes, 'postit.yaml');
  if ((manifest['postit'] as int? ?? 0) > snapshotVersion) {
    throw const FormatException('This snapshot is from a newer PostIt');
  }
  final result = SnapshotResult();
  final fresh =
      repo.children(null).isEmpty &&
      repo.environments().isEmpty &&
      repo.variables(VariableOwner.global).isEmpty;
  if (fresh) {
    if (manifest['id'] is String) {
      repo.restoreWorkspaceId(manifest['id'] as String);
    }
    repo.name = '${manifest['name'] ?? repo.name}';
    if (manifest['settings'] is Map) {
      repo.settings = (manifest['settings'] as Map).cast<String, Object?>();
    }
  }

  // attachments first so requests can refer to them
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

  final globals = files['globals.yaml'];
  if (globals != null) {
    final have = repo.variables(VariableOwner.global);
    final keys = have.map((v) => v.key).toSet();
    final add = _readVars(_doc(globals, 'globals.yaml')['variables'])
        .where((v) => !keys.contains(v.key));
    if (add.isNotEmpty) {
      repo.saveVariables(VariableOwner.global, [...have, ...add]);
    }
  }

  final envOrder = [
    for (final id in (manifest['environments'] as List? ?? const [])) '$id',
  ];
  final envDocs =
      <Map<String, Object?>>[
        for (final e in files.entries)
          if (e.key.startsWith('environments/') && e.key.endsWith('.yaml'))
            _doc(e.value, e.key),
      ]..sort((a, b) {
        int rank(Map<String, Object?> m) {
          final i = envOrder.indexOf('${m['id']}');
          return i < 0 ? envOrder.length : i;
        }

        final c = rank(a).compareTo(rank(b));
        return c != 0 ? c : '${a['name']}'.compareTo('${b['name']}');
      });
  final names = repo.environments().map((e) => e.name).toSet();
  final ids = repo.environments().map((e) => e.id).toSet();
  for (final d in envDocs) {
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
  if (fresh && manifest['defaultEnvironment'] is String) {
    final id = manifest['defaultEnvironment'] as String;
    if (repo.environments().any((e) => e.id == id)) {
      repo.defaultEnvironmentId = id;
    }
  }

  // Containers by directory, requests by directory.
  final containers = <String, Map<String, Object?>>{};
  final requests = <String, List<(String, Map<String, Object?>)>>{};
  final examples = <Map<String, Object?>>[];
  for (final e in files.entries) {
    final p = e.key;
    if (!p.startsWith('collections/')) continue;
    if (p.endsWith('/_collection.yaml') || p.endsWith('/_folder.yaml')) {
      containers[_dirOf(p)] = {
        ..._doc(e.value, p),
        '_collection': p.endsWith('/_collection.yaml'),
      };
    } else if (p.endsWith('.req.yaml')) {
      requests.putIfAbsent(_dirOf(p), () => []).add((p, _doc(e.value, p)));
    } else if (p.endsWith('.example.yaml')) {
      examples.add(_doc(e.value, p));
    }
  }

  void restoreContainer(String dir, String? parentId) {
    final c = containers[dir]!;
    final id = '${c['id']}';
    final isCollection = c['_collection'] == true;
    if (repo.hasNode(id)) {
      result.conflicts.add(
        '${isCollection ? 'Collection' : 'Folder'} "${c['name']}" already exists',
      );
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
    final order = [for (final o in (c['order'] as List? ?? const [])) '$o'];
    int rank(String id) {
      final i = order.indexOf(id);
      return i < 0 ? order.length : i;
    }

    final kids = <(int, String, void Function())>[];
    for (final sub in containers.keys.where((d) => _dirOf(d) == dir)) {
      kids.add((
        rank('${containers[sub]!['id']}'),
        sub,
        () => restoreContainer(sub, id),
      ));
    }
    for (final (path, r)
        in requests[dir] ?? const <(String, Map<String, Object?>)>[]) {
      kids.add((
        rank('${r['id']}'),
        path,
        () {
          final rid = '${r['id']}';
          if (repo.hasNode(rid)) {
            result.conflicts.add('Request "${r['name']}" already exists');
            return;
          }
          repo.restoreNode({
            'id': rid,
            'kind': 'request',
            'type': r['type'] ?? 'http',
            'name': r['name'],
            'description': r['description'],
            'auth': r['auth'],
            'scripts': r['scripts'],
            'data': r['data'],
            'extra': r['extra'],
          }, id);
          result.requests++;
        },
      ));
    }
    kids.sort((a, b) {
      final c = a.$1.compareTo(b.$1);
      return c != 0 ? c : a.$2.compareTo(b.$2);
    });
    for (final k in kids) {
      k.$3();
    }
  }

  final topDirs = containers.keys
      .where((d) => _dirOf(d) == 'collections')
      .toList();
  final collOrder = [
    for (final id in (manifest['collections'] as List? ?? const [])) '$id',
  ];
  int collRank(String dir) {
    final i = collOrder.indexOf('${containers[dir]!['id']}');
    return i < 0 ? collOrder.length : i;
  }

  topDirs.sort((a, b) {
    final c = collRank(a).compareTo(collRank(b));
    return c != 0 ? c : a.compareTo(b);
  });
  for (final d in topDirs) {
    restoreContainer(d, null);
  }

  for (final e in examples) {
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
  return result;
}
