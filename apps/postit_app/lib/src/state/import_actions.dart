import 'dart:convert';

import 'package:postit_core/postit_core.dart';
import 'package:postit_import/postit_import.dart';
import 'package:postit_storage/postit_storage.dart';

import 'session.dart';
import 'variables.dart';

class ImportOutcome {
  const ImportOutcome(this.message, {this.warnings = const [], this.nodeId});

  final String message;
  final List<String> warnings;

  /// The created request or collection.
  final String? nodeId;
}

/// Imports pasted [text]: a cURL command, a Postman collection or a Postman
/// environment (FR-IO-001/002). Throws [FormatException] with a message fit
/// for the user when nothing is recognised.
ImportOutcome importText(
  WorkspaceSession s,
  String text, {
  String? intoCollection,
}) {
  final trimmed = text.trim();
  if (trimmed.isEmpty) throw const FormatException('Nothing to import');

  if (looksLikeCurl(trimmed)) {
    final parsed = parseCurl(trimmed);
    var target = intoCollection;
    target ??=
        s.repo
            .children(null)
            .where((n) => n.name == 'Imported')
            .firstOrNull
            ?.id ??
        s.repo.createCollection('Imported');
    final name = _requestName(parsed.item);
    final id = s.repo.createRequest(
      target,
      HttpRequestItem(
        id: '',
        name: name,
        method: parsed.item.method,
        url: parsed.item.url,
        params: parsed.item.params,
        pathVars: parsed.item.pathVars,
        headers: parsed.item.headers,
        body: parsed.item.body,
        auth: parsed.item.auth,
        settings: parsed.item.settings,
      ),
    );
    return ImportOutcome(
      'Imported "$name"',
      warnings: parsed.warnings,
      nodeId: id,
    );
  }

  Object? json;
  try {
    json = jsonDecode(trimmed);
  } on FormatException {
    throw const FormatException(
      'Not recognised. Paste a cURL command or Postman JSON.',
    );
  }
  if (looksLikePostmanCollection(json)) {
    final r = importPostmanCollection(json);
    final id = saveImportedCollection(s.repo, r.collection);
    return ImportOutcome(
      'Imported collection "${r.collection.name}"',
      warnings: r.warnings,
      nodeId: id,
    );
  }
  if (looksLikePostmanEnvironment(json)) {
    final env = importPostmanEnvironment(json);
    final id = Ulid.generate();
    var name = env.name;
    final taken = s.repo.environments().map((e) => e.name).toSet();
    for (var n = 2; taken.contains(name); n++) {
      name = '${env.name} ($n)';
    }
    s.repo.saveEnvironment(Environment(id: id, name: name));
    final seen = <String>{};
    saveVariables(
      s,
      VariableOwner.environment(id),
      [
        for (final v in env.variables.reversed)
          if (seen.add(v.key)) v,
      ].reversed.toList(),
    );
    return ImportOutcome('Imported environment "$name"');
  }
  throw const FormatException(
    'Not recognised. Paste a cURL command or Postman JSON.',
  );
}

String _requestName(HttpRequestItem i) {
  final (base, _, _) = UrlText.split(i.url);
  final path = base.contains('://')
      ? base.substring(base.indexOf('://') + 3)
      : base;
  return '${i.method} $path';
}

/// Postman v2.1 JSON of a collection, pretty-printed.
String exportCollectionJson(WorkspaceSession s, String collectionId) =>
    const JsonEncoder.withIndent('  ').convert(
      exportPostmanCollection(loadCollectionTree(s.repo, collectionId)),
    );

String requestAsCurl(WorkspaceSession s, String requestId) {
  final item = s.repo.getRequest(requestId);
  return toCurl(
    item,
    auth: effectiveAuth(item.auth, s.repo.authChain(requestId)),
  );
}
