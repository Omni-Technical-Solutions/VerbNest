import 'dart:convert';

import 'package:verbnest_core/verbnest_core.dart';
import 'package:yaml/yaml.dart';

import 'postman.dart';

/// Decodes JSON or YAML text into plain maps and lists, or null when it is
/// neither.
Object? decodeJsonOrYaml(String text) {
  final t = text.trimLeft();
  if (t.startsWith('{') || t.startsWith('[')) {
    try {
      return jsonDecode(text);
    } on FormatException {
      return null;
    }
  }
  try {
    return _plain(loadYaml(text));
  } on Object {
    return null;
  }
}

Object? _plain(Object? v) => switch (v) {
  YamlMap() => {for (final e in v.entries) '${e.key}': _plain(e.value)},
  Map() => {for (final e in v.entries) '${e.key}': _plain(e.value)},
  List() => [for (final e in v) _plain(e)],
  _ => v,
};

bool looksLikeOpenApi(Object? json) {
  if (json is! Map) return false;
  final v = json['openapi'] ?? json['swagger'];
  return v is String && json['paths'] is Map;
}

const _methods = [
  'get',
  'put',
  'post',
  'delete',
  'patch',
  'head',
  'options',
  'trace',
];

/// Imports an OpenAPI 3.0/3.1 or Swagger 2.0 document (FR-IO-004): folders
/// by first tag, a `baseUrl` collection variable, parameters, a body example
/// built from the schema, and the first security scheme as collection auth.
PostmanImport importOpenApi(Object? json) {
  if (!looksLikeOpenApi(json)) {
    throw const FormatException('Not an OpenAPI or Swagger document');
  }
  final doc = _asMap(json);
  final warnings = <String>[];
  final swagger2 = doc['swagger'] != null;
  final info = _asMap(doc['info']);
  final name = _s(info['title']).isEmpty ? 'API' : _s(info['title']);
  final resolver = _Refs(doc, warnings);

  final base = _baseUrl(doc, swagger2);
  final securitySchemes = swagger2
      ? _asMap(doc['securityDefinitions'])
      : _asMap(_asMap(doc['components'])['securitySchemes']);
  final auth = _collectionAuth(doc, securitySchemes, resolver, warnings);

  final byTag = <String, List<ImportNode>>{};
  final loose = <ImportNode>[];
  final tagDescriptions = {
    for (final t in _asList(doc['tags']))
      _s(_asMap(t)['name']): _s(_asMap(t)['description']),
  };

  final paths = _asMap(doc['paths']);
  for (final entry in paths.entries) {
    final path = entry.key;
    if (!path.startsWith('/')) continue;
    final item = _asMap(resolver.deref(entry.value));
    final shared = _asList(item['parameters']);
    for (final m in _methods) {
      final opRaw = item[m];
      if (opRaw == null) continue;
      final op = _asMap(resolver.deref(opRaw));
      final request = _request(
        method: m.toUpperCase(),
        path: path,
        op: op,
        shared: shared,
        swagger2: swagger2,
        doc: doc,
        refs: resolver,
        warnings: warnings,
      );
      final tags = _asList(op['tags']);
      if (tags.isEmpty) {
        loose.add(RequestNode(request));
      } else {
        byTag.putIfAbsent(_s(tags.first), () => []).add(RequestNode(request));
      }
    }
  }

  final folders = <ImportNode>[
    for (final e in byTag.entries)
      FolderNode(
        e.key,
        description: tagDescriptions[e.key] ?? '',
        children: e.value,
      ),
  ];
  final collection = FolderNode(
    name,
    description: _s(info['description']),
    auth: auth,
    variables: [Variable(key: 'baseUrl', value: base)],
    children: [...folders, ...loose],
  );
  return PostmanImport(collection, warnings);
}

String _baseUrl(Map<String, Object?> doc, bool swagger2) {
  if (swagger2) {
    final host = _s(doc['host']);
    final basePath = _s(doc['basePath']);
    final schemes = _asList(doc['schemes']).map(_s).toList();
    if (host.isEmpty) return basePath.replaceAll(RegExp(r'/+$'), '');
    final scheme = schemes.contains('https')
        ? 'https'
        : (schemes.isEmpty ? 'https' : schemes.first);
    return '$scheme://$host${basePath.replaceAll(RegExp(r'/+$'), '')}';
  }
  final servers = _asList(doc['servers']);
  if (servers.isEmpty) return '';
  final s = _asMap(servers.first);
  var url = _s(s['url']);
  _asMap(s['variables']).forEach((k, v) {
    url = url.replaceAll('{$k}', _s(_asMap(v)['default']));
  });
  return url.replaceAll(RegExp(r'/+$'), '');
}

Auth _collectionAuth(
  Map<String, Object?> doc,
  Map<String, Object?> schemes,
  _Refs refs,
  List<String> warnings,
) {
  final security = _asList(doc['security']);
  if (security.isEmpty) return const InheritAuth();
  final first = _asMap(security.first);
  if (first.isEmpty) return const InheritAuth();
  final scheme = _asMap(refs.deref(schemes[first.keys.first]));
  final type = _s(scheme['type']);
  switch (type) {
    case 'http':
      final s = _s(scheme['scheme']).toLowerCase();
      if (s == 'bearer') return const BearerAuth(token: '{{token}}');
      if (s == 'basic') {
        return const BasicAuth(
          username: '{{username}}',
          password: '{{password}}',
        );
      }
    case 'basic':
      return const BasicAuth(
        username: '{{username}}',
        password: '{{password}}',
      );
    case 'apiKey':
      final where = _s(scheme['in']);
      if (where == 'header' || where == 'query') {
        return ApiKeyAuth(
          key: _s(scheme['name']),
          value: '{{apiKey}}',
          addTo: where == 'query'
              ? ApiKeyLocation.query
              : ApiKeyLocation.header,
        );
      }
  }
  warnings.add(
    'Security scheme "${first.keys.first}" ($type) was not imported',
  );
  return const InheritAuth();
}

HttpRequestItem _request({
  required String method,
  required String path,
  required Map<String, Object?> op,
  required List<Object?> shared,
  required bool swagger2,
  required Map<String, Object?> doc,
  required _Refs refs,
  required List<String> warnings,
}) {
  final name = _s(op['summary']).isNotEmpty
      ? _s(op['summary'])
      : (_s(op['operationId']).isNotEmpty
            ? _s(op['operationId'])
            : '$method $path');

  // Operation parameters override path-level ones with the same name and place.
  final merged = <String, Map<String, Object?>>{};
  for (final raw in [...shared, ..._asList(op['parameters'])]) {
    final p = _asMap(refs.deref(raw));
    merged['${p['in']}:${p['name']}'] = p;
  }

  final params = <KeyValue>[];
  final headers = <KeyValue>[];
  final pathVars = <KeyValue>[];
  Map<String, Object?>? bodyParam;
  final formParams = <Map<String, Object?>>[];
  for (final p in merged.values) {
    final where = _s(p['in']);
    final key = _s(p['name']);
    final required = p['required'] == true;
    final schema = swagger2 ? p : _asMap(refs.deref(p['schema']));
    final value = _exampleText(p, schema, refs);
    switch (where) {
      case 'query':
        params.add(
          KeyValue(
            key: key,
            value: value,
            enabled: required,
            description: _s(p['description']),
          ),
        );
      case 'header':
        if (!const {
          'accept',
          'content-type',
          'authorization',
        }.contains(key.toLowerCase())) {
          headers.add(
            KeyValue(
              key: key,
              value: value,
              enabled: required,
              description: _s(p['description']),
            ),
          );
        }
      case 'path':
        pathVars.add(
          KeyValue(key: key, value: value, description: _s(p['description'])),
        );
      case 'body':
        bodyParam = p;
      case 'formData':
        formParams.add(p);
    }
  }

  var url =
      '{{baseUrl}}${path.replaceAllMapped(RegExp(r'\{([^}]+)\}'), (m) => ':${m[1]}')}';
  url = UrlText.withParams(url, params.where((p) => p.enabled).toList());
  // Disabled params stay listed but out of the URL.
  final allParams = _mergeParams(url, params);

  RequestBody body = const NoBody();
  String? contentType;
  if (swagger2) {
    final consumes = [
      ..._asList(op['consumes']),
      ..._asList(doc['consumes']),
    ].map(_s).toList();
    if (bodyParam != null) {
      contentType = consumes.isNotEmpty ? consumes.first : 'application/json';
      body = _rawBody(
        contentType,
        _schemaExampleText(_asMap(bodyParam['schema']), refs),
      );
    } else if (formParams.isNotEmpty) {
      final multipart =
          formParams.any((p) => _s(p['type']) == 'file') ||
          consumes.contains('multipart/form-data');
      final fields = [
        for (final p in formParams)
          KeyValue(
            key: _s(p['name']),
            value: _s(p['type']) == 'file' ? '' : _exampleText(p, p, refs),
            type: _s(p['type']) == 'file'
                ? KeyValueType.file
                : KeyValueType.text,
          ),
      ];
      body = multipart ? FormDataBody(fields) : UrlEncodedBody(fields);
    }
  } else {
    final rb = _asMap(refs.deref(op['requestBody']));
    final content = _asMap(rb['content']);
    if (content.isNotEmpty) {
      contentType = content.keys.firstWhere(
        (k) => k.contains('json'),
        orElse: () => content.keys.first,
      );
      final media = _asMap(content[contentType]);
      body = _bodyFromMedia(contentType, media, refs);
    }
  }
  if (body is RawBody) {
    // Content-Type for a +json or other vendor type that the body mode does
    // not imply.
    final implied = body.defaultContentType;
    if (contentType != null && contentType != implied) {
      headers.add(KeyValue(key: 'Content-Type', value: contentType));
    }
  }

  final description = [
    _s(op['summary']),
    _s(op['description']),
  ].where((e) => e.isNotEmpty).join('\n\n');
  return HttpRequestItem(
    id: '',
    name: name,
    method: method,
    url: url,
    params: allParams,
    pathVars: pathVars,
    headers: headers,
    body: body,
    description: description,
  );
}

List<KeyValue> _mergeParams(String url, List<KeyValue> declared) {
  final inUrl = UrlText.params(url);
  return [
    ...inUrl.map((p) {
      final d = declared.where((x) => x.key == p.key).firstOrNull;
      return d ?? p;
    }),
    ...declared.where((d) => !d.enabled),
  ];
}

RequestBody _bodyFromMedia(
  String contentType,
  Map<String, Object?> media,
  _Refs refs,
) {
  final schema = _asMap(refs.deref(media['schema']));
  Object? example;
  if (media.containsKey('example')) {
    example = media['example'];
  } else if (media['examples'] is Map &&
      (media['examples'] as Map).isNotEmpty) {
    final first = _asMap(refs.deref((media['examples'] as Map).values.first));
    example = first['value'];
  }
  if (contentType.contains('x-www-form-urlencoded') ||
      contentType.contains('multipart/form-data')) {
    final props = _asMap(_resolveSchema(schema, refs)['properties']);
    final fields = [
      for (final e in props.entries)
        KeyValue(
          key: e.key,
          value: _s(_asMap(refs.deref(e.value))['format']) == 'binary'
              ? ''
              : _scalar(_example(_asMap(refs.deref(e.value)), refs, 0)),
          type: _s(_asMap(refs.deref(e.value))['format']) == 'binary'
              ? KeyValueType.file
              : KeyValueType.text,
        ),
    ];
    return contentType.contains('multipart')
        ? FormDataBody(fields)
        : UrlEncodedBody(fields);
  }
  final value = example ?? (schema.isEmpty ? null : _example(schema, refs, 0));
  return _rawBody(
    contentType,
    value == null ? '' : _encode(value, contentType),
  );
}

RequestBody _rawBody(String contentType, String text) {
  final t = contentType.toLowerCase();
  final lang = t.contains('json')
      ? RawBodyLanguage.json
      : t.contains('xml')
      ? RawBodyLanguage.xml
      : t.contains('html')
      ? RawBodyLanguage.html
      : t.contains('javascript')
      ? RawBodyLanguage.javascript
      : RawBodyLanguage.text;
  return RawBody(lang, text);
}

String _encode(Object value, String contentType) =>
    value is String && !contentType.contains('json')
    ? value
    : const JsonEncoder.withIndent('  ').convert(value);

String _schemaExampleText(Map<String, Object?> schema, _Refs refs) {
  final value = _example(schema, refs, 0);
  return value == null ? '' : const JsonEncoder.withIndent('  ').convert(value);
}

String _exampleText(
  Map<String, Object?> param,
  Map<String, Object?> schema,
  _Refs refs,
) {
  final v = param['example'] ?? _example(schema, refs, 0);
  return _scalar(v);
}

String _scalar(Object? v) =>
    v == null ? '' : (v is Map || v is List ? jsonEncode(v) : '$v');

Map<String, Object?> _resolveSchema(Map<String, Object?> schema, _Refs refs) {
  final s = _asMap(refs.deref(schema));
  final all = _asList(s['allOf']);
  if (all.isEmpty) return s;
  final merged = <String, Object?>{...s}..remove('allOf');
  final props = <String, Object?>{..._asMap(s['properties'])};
  for (final part in all) {
    final p = _resolveSchema(_asMap(part), refs);
    props.addAll(_asMap(p['properties']));
    p.forEach((k, v) => merged.putIfAbsent(k, () => v));
  }
  merged['properties'] = props;
  merged['type'] ??= 'object';
  return merged;
}

/// A plausible value for [schema]: example, default, first enum value, or a
/// placeholder for the type. Recursion is cut at depth 6.
Object? _example(Map<String, Object?> raw, _Refs refs, int depth) {
  if (depth > 6) return null;
  final schema = _resolveSchema(raw, refs);
  if (schema.containsKey('example')) return schema['example'];
  if (schema.containsKey('default')) return schema['default'];
  final en = _asList(schema['enum']);
  if (en.isNotEmpty) return en.first;
  for (final key in ['oneOf', 'anyOf']) {
    final options = _asList(schema[key]);
    if (options.isNotEmpty) {
      return _example(_asMap(options.first), refs, depth + 1);
    }
  }
  var type = schema['type'];
  if (type is List) {
    type = type.firstWhere((t) => t != 'null', orElse: () => null);
  }
  if (type == null && schema['properties'] is Map) type = 'object';
  switch (type) {
    case 'object':
      return {
        for (final e in _asMap(schema['properties']).entries)
          e.key: _example(_asMap(e.value), refs, depth + 1),
      };
    case 'array':
      final items = _asMap(schema['items']);
      return items.isEmpty ? [] : [_example(items, refs, depth + 1)];
    case 'integer':
      return 0;
    case 'number':
      return 0.0;
    case 'boolean':
      return false;
    case 'string':
      return switch (_s(schema['format'])) {
        'date-time' => '2024-01-01T00:00:00Z',
        'date' => '2024-01-01',
        'uuid' => '00000000-0000-0000-0000-000000000000',
        'email' => 'user@example.com',
        'uri' || 'url' => 'https://example.com',
        _ => 'string',
      };
  }
  return null;
}

/// Local `$ref` resolution (`#/components/...`). Remote references are left
/// unresolved and reported once.
class _Refs {
  _Refs(this.doc, this.warnings);

  final Map<String, Object?> doc;
  final List<String> warnings;
  final _warned = <String>{};

  Object? deref(Object? node, [int depth = 0]) {
    if (node is Map && node[r'$ref'] is String && depth < 20) {
      final ref = node[r'$ref'] as String;
      if (!ref.startsWith('#/')) {
        if (_warned.add(ref)) warnings.add('External reference $ref skipped');
        return <String, Object?>{};
      }
      Object? cur = doc;
      for (final part in ref.substring(2).split('/')) {
        final key = part.replaceAll('~1', '/').replaceAll('~0', '~');
        cur = cur is Map ? cur[Uri.decodeComponent(key)] : null;
      }
      return deref(cur, depth + 1);
    }
    return node;
  }
}

Map<String, Object?> _asMap(Object? v) =>
    v is Map ? v.cast<String, Object?>() : <String, Object?>{};
List<Object?> _asList(Object? v) => v is List ? v : const [];
String _s(Object? v) => v == null ? '' : '$v';
