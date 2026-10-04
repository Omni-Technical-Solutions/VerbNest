import 'package:postit_core/postit_core.dart';

/// A node of an imported or exported collection tree.
sealed class ImportNode {
  const ImportNode(this.name);

  final String name;
}

class RequestNode extends ImportNode {
  RequestNode(this.item) : super(item.name);

  final HttpRequestItem item;
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

  /// Things PostIt cannot keep yet (examples, folder scripts, ...).
  final List<String> warnings;
}

const postmanSchema =
    'https://schema.getpostman.com/json/collection/v2.1.0/collection.json';

typedef Json = Map<String, Object?>;

Json _map(Object? v) =>
    v is Map ? v.cast<String, Object?>() : <String, Object?>{};
List<Object?> _list(Object? v) => v is List ? v : const [];
String _str(Object? v) => v is String ? v : '';

/// Whether [json] looks like a Postman collection (v2.0 or v2.1).
bool looksLikePostmanCollection(Object? json) {
  final info = _map(_map(json)['info']);
  return info.containsKey('schema') || info.containsKey('_postman_id');
}

/// Imports a Postman collection v2.0/v2.1 (FR-IO-002).
PostmanImport importPostmanCollection(Object? json) {
  final root = _map(json);
  if (!looksLikePostmanCollection(root)) {
    throw const FormatException('Not a Postman collection');
  }
  final warnings = <String>[];
  final info = _map(root['info']);
  final folder = _folder(
    name: _str(info['name']).isEmpty
        ? 'Imported collection'
        : _str(info['name']),
    description: _description(info['description']),
    node: root,
    warnings: warnings,
    path: '',
  );
  return PostmanImport(folder, warnings);
}

String _description(Object? d) => d is String ? d : _str(_map(d)['content']);

FolderNode _folder({
  required String name,
  required String description,
  required Json node,
  required List<String> warnings,
  required String path,
}) {
  if (_list(node['event']).isNotEmpty) {
    warnings.add(
      'Scripts on "$path$name" were not kept (scripts run per request only)',
    );
  }
  final children = <ImportNode>[];
  for (final raw in _list(node['item'])) {
    final item = _map(raw);
    final itemName = _str(item['name']).isEmpty
        ? 'Untitled'
        : _str(item['name']);
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
      children.add(RequestNode(_request(itemName, item, warnings)));
    }
  }
  return FolderNode(
    name,
    description: description,
    auth: node.containsKey('auth') ? _auth(node['auth']) : const InheritAuth(),
    variables: [
      for (final v in _list(node['variable']))
        if (_str(_map(v)['key']).isNotEmpty)
          Variable(
            key: _str(_map(v)['key']),
            value: _stringify(_map(v)['value']),
            enabled: _map(v)['disabled'] != true,
          ),
    ],
    children: children,
  );
}

String _stringify(Object? v) => v == null ? '' : '$v';

HttpRequestItem _request(String name, Json item, List<String> warnings) {
  final req = item['request'] is String
      ? <String, Object?>{'url': item['request']}
      : _map(item['request']);
  if (_list(item['response']).isNotEmpty) {
    warnings.add('Saved examples of "$name" were not kept');
  }

  final (url, disabledParams, pathVars) = _url(req['url']);
  final headers = [
    for (final h in _list(req['header']))
      KeyValue(
        key: _str(_map(h)['key']),
        value: _stringify(_map(h)['value']),
        enabled: _map(h)['disabled'] != true,
        description: _description(_map(h)['description']),
      ),
  ];

  final extra = <String, Object?>{};
  final body = _body(_map(req['body']), extra, name, warnings);

  var scripts = const Scripts();
  for (final e in _list(item['event'])) {
    final ev = _map(e);
    final exec = _list(_map(ev['script'])['exec']).map(_str).join('\n');
    scripts = switch (ev['listen']) {
      'prerequest' => Scripts(pre: exec, post: scripts.post),
      'test' => Scripts(pre: scripts.pre, post: exec),
      _ => scripts,
    };
  }

  return HttpRequestItem(
    id: '',
    name: name,
    method: _str(req['method']).isEmpty ? 'GET' : _str(req['method']),
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
  final m = _map(u);
  var raw = _str(m['raw']);
  if (raw.isEmpty && m.containsKey('host')) raw = _rebuildUrl(m);
  final disabled = [
    for (final q in _list(m['query']))
      if (_map(q)['disabled'] == true)
        KeyValue(
          key: _str(_map(q)['key']),
          value: _stringify(_map(q)['value']),
          enabled: false,
        ),
  ];
  final values = {
    for (final v in _list(m['variable']))
      _str(_map(v)['key']): _stringify(_map(v)['value']),
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
      v is List ? v.map(_str).join(sep) : _str(v);
  final proto = _str(m['protocol']);
  final port = _str(m['port']);
  final host = join(m['host'], '.') + (port.isEmpty ? '' : ':$port');
  final path = join(m['path'], '/');
  final query = _list(m['query'])
      .where((q) => _map(q)['disabled'] != true)
      .map((q) => '${_str(_map(q)['key'])}=${_stringify(_map(q)['value'])}')
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
      final lang = _str(_map(_map(_map(b['options'])['raw']))['language']);
      final language = switch (lang) {
        'json' => RawBodyLanguage.json,
        'xml' => RawBodyLanguage.xml,
        'html' => RawBodyLanguage.html,
        'javascript' => RawBodyLanguage.javascript,
        _ => RawBodyLanguage.text,
      };
      return RawBody(language, _str(b['raw']));
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
  for (final f in _list(list))
    KeyValue(
      key: _str(_map(f)['key']),
      value: _map(f)['type'] == 'file'
          ? _stringify(_map(f)['src'])
          : _stringify(_map(f)['value']),
      enabled: _map(f)['disabled'] != true,
      description: _description(_map(f)['description']),
      type: _map(f)['type'] == 'file' ? KeyValueType.file : KeyValueType.text,
    ),
];

Auth _auth(Object? a) {
  final m = _map(a);
  final type = _str(m['type']);
  String get(String key) {
    for (final e in _list(m[type])) {
      if (_str(_map(e)['key']) == key) return _stringify(_map(e)['value']);
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
    '' => const InheritAuth(),
    _ => RawAuth({'type': type, type: m[type]}),
  };
}

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
        'response': <Object?>[],
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
    RawAuth(:final json) => json,
  };
}

// ---- environments ---------------------------------------------------------

/// Whether [json] is a Postman environment or globals export.
bool looksLikePostmanEnvironment(Object? json) {
  final m = _map(json);
  return m['values'] is List && !m.containsKey('info');
}

/// Imports a Postman environment or globals file. `secret` entries become
/// secret variables.
({String name, List<Variable> variables}) importPostmanEnvironment(
  Object? json,
) {
  final m = _map(json);
  if (!looksLikePostmanEnvironment(m)) {
    throw const FormatException('Not a Postman environment');
  }
  return (
    name: _str(m['name']).isEmpty ? 'Imported environment' : _str(m['name']),
    variables: [
      for (final v in _list(m['values']))
        if (_str(_map(v)['key']).isNotEmpty)
          Variable(
            key: _str(_map(v)['key']),
            value: _stringify(_map(v)['value']),
            secret: _map(v)['type'] == 'secret',
            enabled: _map(v)['enabled'] != false,
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
