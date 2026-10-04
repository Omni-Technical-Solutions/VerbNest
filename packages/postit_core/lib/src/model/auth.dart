/// Authorization config (FR-AUTH-001). Unknown types round-trip as [RawAuth]
/// so data written by a newer version is never lost.
sealed class Auth {
  const Auth();

  String get type;

  Map<String, Object?> toJson();

  factory Auth.fromJson(Map<String, Object?>? json) {
    if (json == null) return const InheritAuth();
    return switch (json['type']) {
      'inherit' => const InheritAuth(),
      'none' => const NoAuth(),
      'apikey' => ApiKeyAuth(
        key: json['key'] as String? ?? '',
        value: json['value'] as String? ?? '',
        addTo: json['addTo'] == 'query'
            ? ApiKeyLocation.query
            : ApiKeyLocation.header,
      ),
      'bearer' => BearerAuth(token: json['token'] as String? ?? ''),
      'basic' => BasicAuth(
        username: json['username'] as String? ?? '',
        password: json['password'] as String? ?? '',
      ),
      'oauth2' when OAuth2Auth.supports(json['grantType']) => OAuth2Auth(
        grant: OAuth2Grant.fromWire(json['grantType'] as String),
        tokenUrl: json['tokenUrl'] as String? ?? '',
        clientId: json['clientId'] as String? ?? '',
        clientSecret: json['clientSecret'] as String? ?? '',
        scope: json['scope'] as String? ?? '',
        username: json['username'] as String? ?? '',
        password: json['password'] as String? ?? '',
        clientAuthInBody: json['clientAuth'] == 'body',
      ),
      _ => RawAuth(Map.of(json)),
    };
  }
}

class InheritAuth extends Auth {
  const InheritAuth();

  @override
  String get type => 'inherit';

  @override
  Map<String, Object?> toJson() => {'type': type};
}

class NoAuth extends Auth {
  const NoAuth();

  @override
  String get type => 'none';

  @override
  Map<String, Object?> toJson() => {'type': type};
}

enum ApiKeyLocation { header, query }

class ApiKeyAuth extends Auth {
  const ApiKeyAuth({
    required this.key,
    required this.value,
    this.addTo = ApiKeyLocation.header,
  });

  final String key;
  final String value;
  final ApiKeyLocation addTo;

  @override
  String get type => 'apikey';

  @override
  Map<String, Object?> toJson() => {
    'type': type,
    'key': key,
    'value': value,
    'addTo': addTo.name,
  };
}

class BearerAuth extends Auth {
  const BearerAuth({required this.token});

  final String token;

  @override
  String get type => 'bearer';

  @override
  Map<String, Object?> toJson() => {'type': type, 'token': token};
}

class BasicAuth extends Auth {
  const BasicAuth({required this.username, required this.password});

  final String username;
  final String password;

  @override
  String get type => 'basic';

  @override
  Map<String, Object?> toJson() => {
    'type': type,
    'username': username,
    'password': password,
  };
}

enum OAuth2Grant {
  clientCredentials('client_credentials'),
  password('password');

  const OAuth2Grant(this.wire);

  final String wire;

  static OAuth2Grant fromWire(String v) =>
      values.firstWhere((g) => g.wire == v);
}

/// OAuth 2.0 token-endpoint grants that need no browser (FR-AUTH-002).
/// Interactive flows (authorization code, PKCE) are not part of this type.
class OAuth2Auth extends Auth {
  const OAuth2Auth({
    required this.grant,
    this.tokenUrl = '',
    this.clientId = '',
    this.clientSecret = '',
    this.scope = '',
    this.username = '',
    this.password = '',
    this.clientAuthInBody = false,
  });

  final OAuth2Grant grant;
  final String tokenUrl;
  final String clientId;
  final String clientSecret;
  final String scope;
  final String username;
  final String password;

  /// Send client credentials in the form body instead of a Basic header.
  final bool clientAuthInBody;

  static bool supports(Object? grantType) =>
      OAuth2Grant.values.any((g) => g.wire == grantType);

  @override
  String get type => 'oauth2';

  OAuth2Auth copyWith({
    OAuth2Grant? grant,
    String? tokenUrl,
    String? clientId,
    String? clientSecret,
    String? scope,
    String? username,
    String? password,
    bool? clientAuthInBody,
  }) => OAuth2Auth(
    grant: grant ?? this.grant,
    tokenUrl: tokenUrl ?? this.tokenUrl,
    clientId: clientId ?? this.clientId,
    clientSecret: clientSecret ?? this.clientSecret,
    scope: scope ?? this.scope,
    username: username ?? this.username,
    password: password ?? this.password,
    clientAuthInBody: clientAuthInBody ?? this.clientAuthInBody,
  );

  /// Applies [f] (e.g. variable substitution) to every text field.
  OAuth2Auth mapText(String Function(String) f) => OAuth2Auth(
    grant: grant,
    tokenUrl: f(tokenUrl),
    clientId: f(clientId),
    clientSecret: f(clientSecret),
    scope: f(scope),
    username: f(username),
    password: f(password),
    clientAuthInBody: clientAuthInBody,
  );

  @override
  Map<String, Object?> toJson() => {
    'type': type,
    'grantType': grant.wire,
    'tokenUrl': tokenUrl,
    'clientId': clientId,
    'clientSecret': clientSecret,
    if (scope.isNotEmpty) 'scope': scope,
    if (grant == OAuth2Grant.password) ...{
      'username': username,
      'password': password,
    },
    'clientAuth': clientAuthInBody ? 'body' : 'header',
  };
}

/// An auth type this version does not understand (e.g. a flow that is not
/// supported). Kept verbatim.
class RawAuth extends Auth {
  const RawAuth(this.json);

  final Map<String, Object?> json;

  @override
  String get type => json['type'] as String? ?? 'unknown';

  @override
  Map<String, Object?> toJson() => json;
}

/// Resolves [InheritAuth] by walking [chain] from the request's parent up to
/// the collection (FR-COL-002). Returns [NoAuth] when nothing sets auth.
Auth effectiveAuth(Auth own, Iterable<Auth> chain) {
  if (own is! InheritAuth) return own;
  for (final a in chain) {
    if (a is! InheritAuth) return a;
  }
  return const NoAuth();
}
