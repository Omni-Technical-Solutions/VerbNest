import 'dart:convert';

import 'package:verbnest_core/verbnest_core.dart';

import 'json_util.dart';

export 'json_util.dart' show Json;
export 'postman_environment.dart';
export 'postman_export.dart';

/// A node of an imported or exported collection tree.
sealed class ImportNode {
  const ImportNode(this.name);

  final String name;
}

/// A saved response (Postman "example") that belongs to a request.
class ImportedExample {
  const ImportedExample({
    required this.name,
    required this.status,
    this.reason = '',
    this.headers = const [],
    this.body = '',
    this.method = 'GET',
    this.url = '',
  });

  final String name;
  final int status;
  final String reason;
  final List<(String, String)> headers;
  final String body;
  final String method;
  final String url;
}

class RequestNode extends ImportNode {
  RequestNode(this.item, {this.examples = const []}) : super(item.name);

  final HttpRequestItem item;
  final List<ImportedExample> examples;
}

/// A collection (root) or folder.
class FolderNode extends ImportNode {
  FolderNode(
    super.name, {
    this.description = '',
    this.auth = const InheritAuth(),
    this.variables = const [],
    this.children = const [],
  });

  final String description;
  final Auth auth;
  final List<Variable> variables;
  final List<ImportNode> children;
}

class PostmanImport {
  PostmanImport(this.collection, this.warnings);

  final FolderNode collection;

  /// Things VerbNest cannot keep yet (folder scripts, ...).
  final List<String> warnings;
}

const postmanSchema =
    'https://schema.getpostman.com/json/collection/v2.1.0/collection.json';

/// Whether [json] looks like a Postman collection (v2.0 or v2.1).
bool looksLikePostmanCollection(Object? json) {
  final info = asJsonMap(asJsonMap(json)['info']);
  return info.containsKey('schema') || info.containsKey('_postman_id');
}

/// Imports a Postman collection v2.0/v2.1 (FR-IO-002).
PostmanImport importPostmanCollection(Object? json) {
  final root = asJsonMap(json);
  if (!looksLikePostmanCollection(root)) {
    throw const FormatException('Not a Postman collection');
  }
  final warnings = <String>[];
  final info = asJsonMap(root['info']);
  final folder = _folder(
    name: asJsonString(info['name']).isEmpty
        ? 'Imported collection'
        : asJsonString(info['name']),
    description: _description(info['description']),
    node: root,
    warnings: warnings,
    path: '',
  );
  return PostmanImport(folder, warnings);
}

String _description(Object? d) =>
    d is String ? d : asJsonString(asJsonMap(d)['content']);

FolderNode _folder({
  required String name,
  required String description,
  required Json node,
  required List<String> warnings,
  required String path,
}) {
  if (asJsonList(node['event']).isNotEmpty) {
    warnings.add(
      'Scripts on "$path$name" were not kept (scripts run per request only)',
    );
  }
  final children = <ImportNode>[];
  for (final raw in asJsonList(node['item'])) {
    final item = asJsonMap(raw);
    final itemName = asJsonString(item['name']).isEmpty
        ? 'Untitled'
        : asJsonString(item['name']);
    if (item.containsKey('item')) {
      children.add(
        _folder(
          name: itemName,
          description: _description(item['description']),
          node: item,
          warnings: warnings,
          path: '$path$name/',
        ),
      );
    } else {
      children.add(
        RequestNode(
          _request(itemName, item, warnings),
          examples: _examples(item),
        ),
      );
    }
  }
  return FolderNode(
    name,
    description: description,
    auth: node.containsKey('auth') ? _auth(node['auth']) : const InheritAuth(),
    variables: [
      for (final v in asJsonList(node['variable']))
        if (asJsonString(asJsonMap(v)['key']).isNotEmpty)
          Variable(
            key: asJsonString(asJsonMap(v)['key']),
            value: jsonText(asJsonMap(v)['value']),
            enabled: asJsonMap(v)['disabled'] != true,
          ),
    ],
    children: children,
  );
}

List<ImportedExample> _examples(Json item) {
  return [
    for (final raw in asJsonList(item['response']))
      () {
        final r = asJsonMap(raw);
        final original = asJsonMap(r['originalRequest']);
        final status = r['code'] is int ? r['code'] as int : 200;
        final (url, _, _) = _url(original['url']);
        return ImportedExample(
          name: asJsonString(r['name']).isEmpty
              ? '$status'
              : asJsonString(r['name']),
          status: status,
          reason: asJsonString(r['status']),
          headers: [
            for (final h in asJsonList(r['header']))
              (
                asJsonString(asJsonMap(h)['key']),
                jsonText(asJsonMap(h)['value']),
              ),
          ],
          body: asJsonString(r['body']),
          method: asJsonString(original['method']).isEmpty
              ? 'GET'
              : asJsonString(original['method']),
          url: url,
        );
      }(),
  ];
}

HttpRequestItem _request(String name, Json item, List<String> warnings) {
  final req = item['request'] is String
      ? <String, Object?>{'url': item['request']}
      : asJsonMap(item['request']);

  final (url, disabledParams, pathVars) = _url(req['url']);
  final headers = [
    for (final h in asJsonList(req['header']))
      KeyValue(
        key: asJsonString(asJsonMap(h)['key']),
        value: jsonText(asJsonMap(h)['value']),
        enabled: asJsonMap(h)['disabled'] != true,
        description: _description(asJsonMap(h)['description']),
      ),
  ];

  final extra = <String, Object?>{};
  final body = _body(asJsonMap(req['body']), extra, name, warnings);

  var scripts = const Scripts();
  for (final e in asJsonList(item['event'])) {
    final ev = asJsonMap(e);
    final exec = asJsonList(asJsonMap(ev['script'])['exec'])
        .map(asJsonString)
        .join('\n');
    scripts = switch (ev['listen']) {
      'prerequest' => Scripts(pre: exec, post: scripts.post),
      'test' => Scripts(pre: scripts.pre, post: exec),
      _ => scripts,
    };
  }

  return HttpRequestItem(
    id: '',
    name: name,
    method: asJsonString(req['method']).isEmpty
        ? 'GET'
        : asJsonString(req['method']),
    url: url,
    params: [...UrlText.params(url), ...disabledParams],
    pathVars: pathVars,
    headers: headers,
    body: body,
    auth: req.containsKey('auth') ? _auth(req['auth']) : const InheritAuth(),
    scripts: scripts,
    description: _description(req['description']),
    extra: extra,
  );
}

(String, List<KeyValue>, List<KeyValue>) _url(Object? u) {
  if (u is String) {
    return (
      u,
      const [],
      [for (final n in UrlText.pathVariables(u)) KeyValue(key: n)],
    );
  }
  final m = asJsonMap(u);
  var raw = asJsonString(m['raw']);
  if (raw.isEmpty && m.containsKey('host')) raw = _rebuildUrl(m);
  final disabled = [
    for (final q in asJsonList(m['query']))
      if (asJsonMap(q)['disabled'] == true)
        KeyValue(
          key: asJsonString(asJsonMap(q)['key']),
          value: jsonText(asJsonMap(q)['value']),
          enabled: false,
        ),
  ];
  final values = {
    for (final v in asJsonList(m['variable']))
      asJsonString(asJsonMap(v)['key']): jsonText(asJsonMap(v)['value']),
  };
  return (
    raw,
    disabled,
    [
      for (final n in UrlText.pathVariables(raw))
        KeyValue(key: n, value: values[n] ?? ''),
    ],
  );
}

String _rebuildUrl(Json m) {
  String join(Object? v, String sep) =>
      v is List ? v.map(asJsonString).join(sep) : asJsonString(v);
  final proto = asJsonString(m['protocol']);
  final port = asJsonString(m['port']);
  final host = join(m['host'], '.') + (port.isEmpty ? '' : ':$port');
  final path = join(m['path'], '/');
  final query = asJsonList(m['query'])
      .where((q) => asJsonMap(q)['disabled'] != true)
      .map(
        (q) =>
            '${asJsonString(asJsonMap(q)['key'])}=${jsonText(asJsonMap(q)['value'])}',
      )
      .join('&');
  return '${proto.isEmpty ? '' : '$proto://'}$host${path.isEmpty ? '' : '/$path'}'
      '${query.isEmpty ? '' : '?$query'}';
}

RequestBody _body(
  Json b,
  Map<String, Object?> extra,
  String name,
  List<String> warnings,
) {
  switch (b['mode']) {
    case null:
      return const NoBody();
    case 'raw':
      final lang = asJsonString(
        asJsonMap(asJsonMap(asJsonMap(b['options'])['raw']))['language'],
      );
      final language = switch (lang) {
        'json' => RawBodyLanguage.json,
        'xml' => RawBodyLanguage.xml,
        'html' => RawBodyLanguage.html,
        'javascript' => RawBodyLanguage.javascript,
        _ => RawBodyLanguage.text,
      };
      return RawBody(language, asJsonString(b['raw']));
    case 'graphql':
      final g = asJsonMap(b['graphql']);
      final vars = g['variables'];
      return GraphqlBody(
        query: asJsonString(g['query']),
        variables: vars is String
            ? vars
            : (vars is Map && vars.isNotEmpty ? jsonEncode(vars) : ''),
        operationName: asJsonString(g['operationName']),
      );
    case 'urlencoded':
      return UrlEncodedBody(_fields(b['urlencoded']));
    case 'formdata':
      return FormDataBody(_fields(b['formdata']));
    case 'file':
      warnings.add('The file body of "$name" needs to be picked again');
      return const BinaryBody(null);
    default:
      // Kept verbatim so exporting writes it back unchanged.
      extra['postman.body'] = b;
      warnings.add('Body mode "${b['mode']}" of "$name" is not editable yet');
      return const NoBody();
  }
}

List<KeyValue> _fields(Object? list) => [
  for (final f in asJsonList(list))
    KeyValue(
      key: asJsonString(asJsonMap(f)['key']),
      value: asJsonMap(f)['type'] == 'file'
          ? jsonText(asJsonMap(f)['src'])
          : jsonText(asJsonMap(f)['value']),
      enabled: asJsonMap(f)['disabled'] != true,
      description: _description(asJsonMap(f)['description']),
      type: asJsonMap(f)['type'] == 'file'
          ? KeyValueType.file
          : KeyValueType.text,
    ),
];

Auth _auth(Object? a) {
  final m = asJsonMap(a);
  final type = asJsonString(m['type']);
  String get(String key) {
    for (final e in asJsonList(m[type])) {
      if (asJsonString(asJsonMap(e)['key']) == key) {
        return jsonText(asJsonMap(e)['value']);
      }
    }
    return '';
  }

  return switch (type) {
    'noauth' => const NoAuth(),
    'bearer' => BearerAuth(token: get('token')),
    'basic' => BasicAuth(username: get('username'), password: get('password')),
    'apikey' => ApiKeyAuth(
      key: get('key'),
      value: get('value'),
      addTo: get('in') == 'query'
          ? ApiKeyLocation.query
          : ApiKeyLocation.header,
    ),
    'digest' => DigestAuth(
      username: get('username'),
      password: get('password'),
    ),
    'awsv4' => AwsV4Auth(
      accessKey: get('accessKey'),
      secretKey: get('secretKey'),
      region: get('region'),
      service: get('service'),
      sessionToken: get('sessionToken'),
    ),
    'jwt'
        when JwtAlgorithm.values.any(
          (a) => a.label == get('algorithm') || a.name == get('algorithm'),
        ) =>
      JwtAuth(
        algorithm: JwtAlgorithm.values.firstWhere(
          (a) => a.label == get('algorithm') || a.name == get('algorithm'),
        ),
        secret: get('secret'),
        payload: get('payload').isEmpty ? '{}' : get('payload'),
        prefix: get('headerPrefix').isEmpty ? 'Bearer' : get('headerPrefix'),
      ),
    'oauth2' when OAuth2Auth.supports(_grant(get('grant_type'))) => OAuth2Auth(
      grant: OAuth2Grant.fromWire(_grant(get('grant_type'))),
      authUrl: get('authUrl'),
      usePkce: get('grant_type') != 'authorization_code',
      tokenUrl: get('accessTokenUrl'),
      clientId: get('clientId'),
      clientSecret: get('clientSecret'),
      scope: get('scope'),
      username: get('username'),
      password: get('password'),
      clientAuthInBody: get('client_authentication') == 'body',
    ),
    '' => const InheritAuth(),
    _ => RawAuth({'type': type, type: m[type]}),
  };
}

/// Postman names the PKCE variant of the code grant separately.
String _grant(String g) =>
    g == 'authorization_code_with_pkce' ? 'authorization_code' : g;
