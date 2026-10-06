enum NodeKind { collection, folder, request }

/// A row of the collection tree, without its type-specific document.
class NodeInfo {
  const NodeInfo({
    required this.id,
    required this.parentId,
    required this.kind,
    required this.type,
    required this.name,
    required this.position,
    this.method,
  });

  final String id;
  final String? parentId;
  final NodeKind kind;

  /// Request type (`http`, ...); null for collections and folders.
  final String? type;
  final String name;
  final int position;

  /// HTTP method of a request, for sidebar badges; null otherwise.
  final String? method;

  bool get isContainer => kind != NodeKind.request;
}

class RevisionInfo {
  const RevisionInfo({required this.rev, required this.savedAt});

  final int rev;
  final DateTime savedAt;
}
