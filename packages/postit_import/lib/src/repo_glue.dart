import 'dart:convert';
import 'dart:typed_data';

import 'package:postit_core/postit_core.dart';
import 'package:postit_storage/postit_storage.dart';

import 'postman.dart';

/// Writes an imported collection into [repo] and returns its collection id.
String saveImportedCollection(WorkspaceRepository repo, FolderNode root) {
  final id = repo.createCollection(root.name);
  _saveContainer(repo, id, root);
  _saveChildren(repo, id, root);
  return id;
}

void _saveContainer(WorkspaceRepository repo, String id, FolderNode f) {
  if (f.auth is! InheritAuth) repo.setContainerAuth(id, f.auth);
  if (f.description.isNotEmpty) repo.setDescription(id, f.description);
  if (f.variables.isNotEmpty) {
    repo.saveVariables(_owner(repo, id), _dedupe(f.variables));
  }
}

VariableOwner _owner(WorkspaceRepository repo, String id) =>
    repo.node(id).parentId == null
    ? VariableOwner.collection(id)
    : VariableOwner.folder(id);

/// The workspace rejects repeated keys within a scope; keep the last.
List<Variable> _dedupe(List<Variable> vars) {
  final byKey = {for (final v in vars) v.key: v};
  return byKey.values.toList();
}

void _saveChildren(WorkspaceRepository repo, String parentId, FolderNode f) {
  for (final child in f.children) {
    switch (child) {
      case FolderNode():
        final id = repo.createFolder(parentId, child.name);
        _saveContainer(repo, id, child);
        _saveChildren(repo, id, child);
      case RequestNode():
        final id = repo.createRequest(parentId, child.item);
        for (final e in child.examples) {
          repo.addExample(id, e.name, {
            'status': e.status,
            'reason': e.reason,
            'headers': [
              for (final (k, v) in e.headers) [k, v],
            ],
            'request': {'method': e.method, 'url': e.url},
          }, Uint8List.fromList(utf8.encode(e.body)));
        }
    }
  }
}

/// Reads a collection (or folder) from [repo] for export.
FolderNode loadCollectionTree(WorkspaceRepository repo, String id) {
  final info = repo.node(id);
  return FolderNode(
    info.name,
    description: repo.description(id),
    auth: repo.containerAuth(id),
    variables: repo.variables(_owner(repo, id)),
    children: [
      for (final c in repo.children(id))
        c.isContainer ? loadCollectionTree(repo, c.id) : _request(repo, c.id),
    ],
  );
}

RequestNode _request(WorkspaceRepository repo, String id) => RequestNode(
  repo.getRequest(id),
  examples: [
    for (final e in repo.examples(id))
      ImportedExample(
        name: e.name,
        status: (e.data['status'] as int?) ?? 200,
        reason: '${e.data['reason'] ?? ''}',
        headers: [
          for (final h in (e.data['headers'] as List? ?? const []))
            ('${(h as List)[0]}', '${h[1]}'),
        ],
        body: utf8.decode(e.body, allowMalformed: true),
        method: '${(e.data['request'] as Map?)?['method'] ?? 'GET'}',
        url: '${(e.data['request'] as Map?)?['url'] ?? ''}',
      ),
  ],
);
