import 'dart:typed_data';

import 'models.dart' show NodeKind;

/// A saved request/response pair.
class ExampleInfo {
  const ExampleInfo({
    required this.id,
    required this.requestId,
    required this.name,
    required this.data,
    required this.body,
  });

  final String id;
  final String requestId;
  final String name;

  /// `status`, `reason`, `headers` (list of [name, value]), `request`.
  final Map<String, Object?> data;
  final Uint8List body;
}

/// Who owns a set of variables.
class VariableOwner {
  const VariableOwner._(this.kind, this.id);

  factory VariableOwner.environment(String id) =>
      VariableOwner._('environment', id);
  factory VariableOwner.collection(String id) =>
      VariableOwner._('collection', id);
  factory VariableOwner.folder(String id) => VariableOwner._('folder', id);
  static const global = VariableOwner._('global', '');

  final String kind;
  final String id;
}

/// Metadata of a stored attachment.
class AttachmentInfo {
  const AttachmentInfo({
    required this.id,
    required this.name,
    required this.size,
    this.mime,
  });

  final String id;
  final String name;
  final String? mime;
  final int size;
}

/// One row of searchable text.
class SearchDoc {
  const SearchDoc({
    required this.id,
    required this.parentId,
    required this.kind,
    required this.name,
    this.method,
    this.url,
    this.meta = '',
    this.body = '',
  });

  final String id;
  final String? parentId;
  final NodeKind kind;
  final String name;
  final String? method;
  final String? url;
  final String meta;
  final String body;
}
