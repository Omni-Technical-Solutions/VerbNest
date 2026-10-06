import 'dart:convert';

import 'package:verbnest_core/verbnest_core.dart';
import 'package:verbnest_import/verbnest_import.dart';
import 'package:verbnest_storage/verbnest_storage.dart';

import 'session.dart';
import 'variables.dart';

class ImportOutcome {
  const ImportOutcome(this.message, {this.warnings = const [], this.nodeId});

  final String message;
  final List<String> warnings;

  /// The created request or collection.
  final String? nodeId;
}

/// Largest import accepted, in characters. Parsing builds the whole document
/// in memory, so a huge file could exhaust it on a phone.
const maxImportChars = 64 * 1024 * 1024;

/// Imports pasted [text]: a cURL command, a Postman collection or a Postman
/// environment (FR-IO-001/002). Throws [FormatException] with a message fit
/// for the user when nothing is recognised.
ImportOutcome importText(
  WorkspaceSession s,
  String text, {
  String? intoCollection,
}) {
  if (text.length > maxImportChars) {
    throw const FormatException(
      'This file is too large to import (over 64 MB)',
    );
  }
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

  final json = decodeJsonOrYaml(trimmed);
  if (json == null) throw const FormatException(_notRecognised);

  PostmanImport? collection;
  if (looksLikePostmanCollection(json)) {
    collection = importPostmanCollection(json);
  } else if (looksLikeOpenApi(json)) {
    collection = importOpenApi(json);
  } else if (looksLikeHar(json)) {
    collection = importHar(json);
  }
  if (collection != null) {
    final id = saveImportedCollection(s.repo, collection.collection);
    return ImportOutcome(
      'Imported collection "${collection.collection.name}"',
      warnings: collection.warnings,
      nodeId: id,
    );
  }
  if (looksLikePostmanEnvironment(json)) {
    final name = _importEnvironment(s, importPostmanEnvironment(json));
    return ImportOutcome('Imported environment "$name"');
  }
  if (json is Map &&
      (json['collections'] is List || json['environments'] is List)) {
    return _importDump(s, json);
  }
  throw const FormatException(_notRecognised);
}

const _notRecognised =
    'Not recognised. Paste a cURL command, Postman JSON, OpenAPI/Swagger '
    '(JSON or YAML) or HAR.';

String _importEnvironment(
  WorkspaceSession s,
  ({String name, List<Variable> variables}) env,
) {
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
  return name;
}

/// A single JSON file holding `collections` and `environments` arrays (the
/// shape of Postman's older backup). Postman's current zip data dump has to
/// be unzipped and its files imported one by one.
ImportOutcome _importDump(WorkspaceSession s, Map<Object?, Object?> dump) {
  var collections = 0;
  var environments = 0;
  final warnings = <String>[];
  String? firstId;
  for (final c in (dump['collections'] as List? ?? const [])) {
    if (!looksLikePostmanCollection(c)) {
      warnings.add('Skipped a collection in a format Verbnest does not read');
      continue;
    }
    final r = importPostmanCollection(c);
    final id = saveImportedCollection(s.repo, r.collection);
    firstId ??= id;
    warnings.addAll(r.warnings);
    collections++;
  }
  for (final e in (dump['environments'] as List? ?? const [])) {
    if (!looksLikePostmanEnvironment(e)) continue;
    _importEnvironment(s, importPostmanEnvironment(e));
    environments++;
  }
  if (collections + environments == 0) {
    throw const FormatException(_notRecognised);
  }
  return ImportOutcome(
    'Imported $collections collections and $environments environments',
    warnings: warnings,
    nodeId: firstId,
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

/// Code for a saved request in [language]. With [resolve] the variables of
/// the active environment are substituted (secrets included), otherwise the
/// `{{names}}` stay.
String requestAsCode(
  WorkspaceSession s,
  String requestId,
  CodeLanguage language, {
  bool resolve = false,
  String? envId,
}) {
  final item = s.repo.getRequest(requestId);
  final auth = effectiveAuth(item.auth, s.repo.authChain(requestId));
  final resolver = resolve
      ? VariableResolver(buildScopes(s, requestId: requestId, envId: envId))
      : null;
  return generateCode(
    language,
    item,
    auth: auth,
    resolve: resolver == null ? null : (t) => resolver.resolve(t).value,
  );
}
