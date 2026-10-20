import 'package:verbnest_core/verbnest_core.dart';

import 'postman.dart';

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
