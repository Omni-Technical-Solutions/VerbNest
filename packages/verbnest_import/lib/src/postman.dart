import 'dart:convert';

import 'package:verbnest_core/verbnest_core.dart';

import 'json_util.dart';

export 'json_util.dart' show Json;

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
            value: _stringify(asJsonMap(v)['value']),
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
                _stringify(asJsonMap(h)['value']),
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

String _stringify(Object? v) => v == null ? '' : '$v';

HttpRequestItem _request(String name, Json item, List<String> warnings) {
  final req = item['request'] is String
      ? <String, Object?>{'url': item['request']}
      : asJsonMap(item['request']);

  final (url, disabledParams, pathVars) = _url(req['url']);
  final headers = [
    for (final h in asJsonList(req['header']))
      KeyValue(
        key: asJsonString(asJsonMap(h)['key']),
        value: _stringify(asJsonMap(h)['value']),
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
          value: _stringify(asJsonMap(q)['value']),
          enabled: false,
        ),
  ];
  final values = {
    for (final v in asJsonList(m['variable']))
      asJsonString(asJsonMap(v)['key']): _stringify(asJsonMap(v)['value']),
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
            '${asJsonString(asJsonMap(q)['key'])}=${_stringify(asJsonMap(q)['value'])}',
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
          ? _stringify(asJsonMap(f)['src'])
          : _stringify(asJsonMap(f)['value']),
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
        return _stringify(asJsonMap(e)['value']);
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

// ---- export ---------------------------------------------------------------

/// Exports [collection] as a Postman v2.1 collection document.
Json exportPostmanCollection(FolderNode collection) {
  return {
    'info': {
      'name': collection.name,
      'schema': postmanSchema,
      if (collection.description.isNotEmpty)
        'description': collection.description,
    },
    'item': [for (final c in collection.children) _exportNode(c)],
    if (collection.auth is! InheritAuth) 'auth': _exportAuth(collection.auth),
    if (collection.variables.isNotEmpty)
      'variable': [
        for (final v in collection.variables)
          {'key': v.key, 'value': v.value, if (!v.enabled) 'disabled': true},
      ],
  };
}

Json _exportNode(ImportNode n) {
  switch (n) {
    case FolderNode():
      return {
        'name': n.name,
        if (n.description.isNotEmpty) 'description': n.description,
        'item': [for (final c in n.children) _exportNode(c)],
        if (n.auth is! InheritAuth) 'auth': _exportAuth(n.auth),
      };
    case RequestNode():
      final i = n.item;
      return {
        'name': i.name,
        if (!i.scripts.isEmpty)
          'event': [
            if (i.scripts.pre.isNotEmpty) _event('prerequest', i.scripts.pre),
            if (i.scripts.post.isNotEmpty) _event('test', i.scripts.post),
          ],
        'request': {
          'method': i.method,
          if (i.auth is! InheritAuth) 'auth': _exportAuth(i.auth),
          'header': [
            for (final h in i.headers)
              {
                'key': h.key,
                'value': h.value,
                if (!h.enabled) 'disabled': true,
                if (h.description.isNotEmpty) 'description': h.description,
              },
          ],
          'body': ?_exportBody(i),
          'url': _exportUrl(i),
          if (i.description.isNotEmpty) 'description': i.description,
        },
        'response': [
          for (final e in n.examples)
            {
              'name': e.name,
              'originalRequest': {'method': e.method, 'url': e.url},
              'status': e.reason,
              'code': e.status,
              'header': [
                for (final (k, v) in e.headers) {'key': k, 'value': v},
              ],
              'body': e.body,
            },
        ],
      };
  }
}

Json _event(String listen, String code) => {
  'listen': listen,
  'script': {'type': 'text/javascript', 'exec': code.split('\n')},
};

Json _exportUrl(HttpRequestItem i) {
  final raw = i.url;
  final (base, _, _) = UrlText.split(raw);
  final scheme = base.contains('://') ? base.indexOf('://') : -1;
  final rest = scheme == -1 ? base : base.substring(scheme + 3);
  final slash = rest.indexOf('/');
  var hostPart = slash == -1 ? rest : rest.substring(0, slash);
  final path = slash == -1 ? '' : rest.substring(slash + 1);
  String? port;
  final colon = hostPart.lastIndexOf(':');
  if (colon != -1 && !hostPart.substring(colon).contains('}')) {
    port = hostPart.substring(colon + 1);
    hostPart = hostPart.substring(0, colon);
  }
  return {
    'raw': raw,
    if (scheme != -1) 'protocol': base.substring(0, scheme),
    'host': hostPart.split('.'),
    'port': ?port,
    if (path.isNotEmpty) 'path': path.split('/'),
    if (i.params.isNotEmpty)
      'query': [
        for (final p in i.params)
          {'key': p.key, 'value': p.value, if (!p.enabled) 'disabled': true},
      ],
    if (i.pathVars.isNotEmpty)
      'variable': [
        for (final v in i.pathVars) {'key': v.key, 'value': v.value},
      ],
  };
}

Json? _exportBody(HttpRequestItem i) {
  final saved = i.extra['postman.body'];
  if (saved is Map && i.body is NoBody) return saved.cast<String, Object?>();
  return switch (i.body) {
    NoBody() => null,
    RawBody(:final text, :final language) => {
      'mode': 'raw',
      'raw': text,
      'options': {
        'raw': {
          'language': language == RawBodyLanguage.text ? 'text' : language.name,
        },
      },
    },
    GraphqlBody(:final query, :final variables) => {
      'mode': 'graphql',
      'graphql': {'query': query, 'variables': variables},
    },
    UrlEncodedBody(:final fields) => {
      'mode': 'urlencoded',
      'urlencoded': [
        for (final f in fields)
          {'key': f.key, 'value': f.value, if (!f.enabled) 'disabled': true},
      ],
    },
    FormDataBody(:final fields) => {
      'mode': 'formdata',
      'formdata': [
        for (final f in fields)
          {
            'key': f.key,
            if (f.type == KeyValueType.file)
              'src': f.value
            else
              'value': f.value,
            'type': f.type == KeyValueType.file ? 'file' : 'text',
            if (!f.enabled) 'disabled': true,
          },
      ],
    },
    BinaryBody() => {'mode': 'file', 'file': <String, Object?>{}},
  };
}

Json _exportAuth(Auth a) {
  List<Json> kv(Map<String, String> m) => [
    for (final e in m.entries)
      {'key': e.key, 'value': e.value, 'type': 'string'},
  ];
  return switch (a) {
    InheritAuth() => {'type': 'noauth'},
    NoAuth() => {'type': 'noauth'},
    BearerAuth(:final token) => {
      'type': 'bearer',
      'bearer': kv({'token': token}),
    },
    BasicAuth(:final username, :final password) => {
      'type': 'basic',
      'basic': kv({'username': username, 'password': password}),
    },
    ApiKeyAuth(:final key, :final value, :final addTo) => {
      'type': 'apikey',
      'apikey': kv({'key': key, 'value': value, 'in': addTo.name}),
    },
    OAuth2Auth() => {
      'type': 'oauth2',
      'oauth2': kv({
        'grant_type': a.grant == OAuth2Grant.authorizationCode && a.usePkce
            ? 'authorization_code_with_pkce'
            : a.grant.wire,
        if (a.authUrl.isNotEmpty) 'authUrl': a.authUrl,
        'accessTokenUrl': a.tokenUrl,
        'clientId': a.clientId,
        'clientSecret': a.clientSecret,
        'scope': a.scope,
        if (a.grant == OAuth2Grant.password) ...{
          'username': a.username,
          'password': a.password,
        },
        'client_authentication': a.clientAuthInBody ? 'body' : 'header',
      }),
    },
    DigestAuth(:final username, :final password) => {
      'type': 'digest',
      'digest': kv({'username': username, 'password': password}),
    },
    AwsV4Auth() => {
      'type': 'awsv4',
      'awsv4': kv({
        'accessKey': a.accessKey,
        'secretKey': a.secretKey,
        'region': a.region,
        'service': a.service,
        if (a.sessionToken.isNotEmpty) 'sessionToken': a.sessionToken,
      }),
    },
    JwtAuth() => {
      'type': 'jwt',
      'jwt': kv({
        'algorithm': a.algorithm.label,
        'secret': a.secret,
        'payload': a.payload,
        'addTokenTo': 'header',
        'headerPrefix': a.prefix,
      }),
    },
    RawAuth(:final json) => json,
  };
}

// ---- environments ---------------------------------------------------------

/// Whether [json] is a Postman environment or globals export.
bool looksLikePostmanEnvironment(Object? json) {
  final m = asJsonMap(json);
  return m['values'] is List && !m.containsKey('info');
}

/// Imports a Postman environment or globals file. `secret` entries become
/// secret variables.
({String name, List<Variable> variables}) importPostmanEnvironment(
  Object? json,
) {
  final m = asJsonMap(json);
  if (!looksLikePostmanEnvironment(m)) {
    throw const FormatException('Not a Postman environment');
  }
  return (
    name: asJsonString(m['name']).isEmpty
        ? 'Imported environment'
        : asJsonString(m['name']),
    variables: [
      for (final v in asJsonList(m['values']))
        if (asJsonString(asJsonMap(v)['key']).isNotEmpty)
          Variable(
            key: asJsonString(asJsonMap(v)['key']),
            value: _stringify(asJsonMap(v)['value']),
            secret: asJsonMap(v)['type'] == 'secret',
            enabled: asJsonMap(v)['enabled'] != false,
          ),
    ],
  );
}

/// Exports variables as a Postman environment. Secret values are exported
/// only when [includeSecrets] is true.
Json exportPostmanEnvironment(
  String name,
  List<Variable> variables, {
  bool includeSecrets = false,
}) => {
  'name': name,
  'values': [
    for (final v in variables)
      {
        'key': v.key,
        'value': v.secret && !includeSecrets ? '' : v.value,
        'type': v.secret ? 'secret' : 'default',
        'enabled': v.enabled,
      },
  ],
  '_postman_variable_scope': 'environment',
};
