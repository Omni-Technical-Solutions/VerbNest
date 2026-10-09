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
        authUrl: json['authUrl'] as String? ?? '',
        usePkce: json['pkce'] as bool? ?? true,
      ),
      'digest' => DigestAuth(
        username: json['username'] as String? ?? '',
        password: json['password'] as String? ?? '',
      ),
      'jwt' => JwtAuth(
        algorithm:
            JwtAlgorithm.values
                .where((a) => a.name == json['algorithm'])
                .firstOrNull ??
            JwtAlgorithm.hs256,
        secret: json['secret'] as String? ?? '',
        payload: json['payload'] as String? ?? '{}',
        prefix: json['prefix'] as String? ?? 'Bearer',
      ),
      'awsv4' => AwsV4Auth(
        accessKey: json['accessKey'] as String? ?? '',
        secretKey: json['secretKey'] as String? ?? '',
        region: json['region'] as String? ?? '',
        service: json['service'] as String? ?? '',
        sessionToken: json['sessionToken'] as String? ?? '',
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
  password('password'),
  authorizationCode('authorization_code'),
  implicit('implicit');

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
    this.authUrl = '',
    this.usePkce = true,
  });

  /// Send a PKCE challenge with the authorization code request.
  final bool usePkce;

  final OAuth2Grant grant;

  /// The browser page where the user signs in (authorization code, implicit).
  final String authUrl;
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
    String? authUrl,
    bool? usePkce,
  }) => OAuth2Auth(
    authUrl: authUrl ?? this.authUrl,
    usePkce: usePkce ?? this.usePkce,
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
    authUrl: f(authUrl),
    usePkce: usePkce,
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
    if (authUrl.isNotEmpty) 'authUrl': authUrl,
    if (grant == OAuth2Grant.authorizationCode) 'pkce': usePkce,
  };

  /// True for flows that need the user to sign in through a browser.
  bool get interactive =>
      grant == OAuth2Grant.authorizationCode || grant == OAuth2Grant.implicit;
}

/// HTTP Digest (RFC 7616). The credentials are used after the server's
/// challenge, so the request is sent twice (FR-AUTH-004).
class DigestAuth extends Auth {
  const DigestAuth({required this.username, required this.password});

  final String username;
  final String password;

  @override
  String get type => 'digest';

  @override
  Map<String, Object?> toJson() => {
    'type': type,
    'username': username,
    'password': password,
  };
}

enum JwtAlgorithm {
  hs256('HS256'),
  hs384('HS384'),
  hs512('HS512');

  const JwtAlgorithm(this.label);
  final String label;
}

/// A bearer JWT signed by VerbNest for each send (FR-AUTH-004). [payload] is
/// JSON text; `iat` is added when the payload does not set it.
class JwtAuth extends Auth {
  const JwtAuth({
    this.algorithm = JwtAlgorithm.hs256,
    this.secret = '',
    this.payload = '{}',
    this.prefix = 'Bearer',
  });

  final JwtAlgorithm algorithm;
  final String secret;
  final String payload;

  /// Word before the token in the Authorization header.
  final String prefix;

  JwtAuth copyWith({
    JwtAlgorithm? algorithm,
    String? secret,
    String? payload,
    String? prefix,
  }) => JwtAuth(
    algorithm: algorithm ?? this.algorithm,
    secret: secret ?? this.secret,
    payload: payload ?? this.payload,
    prefix: prefix ?? this.prefix,
  );

  @override
  String get type => 'jwt';

  @override
  Map<String, Object?> toJson() => {
    'type': type,
    'algorithm': algorithm.name,
    'secret': secret,
    'payload': payload,
    'prefix': prefix,
  };
}

/// AWS Signature Version 4 (FR-AUTH-004).
class AwsV4Auth extends Auth {
  const AwsV4Auth({
    this.accessKey = '',
    this.secretKey = '',
    this.region = '',
    this.service = '',
    this.sessionToken = '',
  });

  final String accessKey;
  final String secretKey;
  final String region;
  final String service;
  final String sessionToken;

  AwsV4Auth copyWith({
    String? accessKey,
    String? secretKey,
    String? region,
    String? service,
    String? sessionToken,
  }) => AwsV4Auth(
    accessKey: accessKey ?? this.accessKey,
    secretKey: secretKey ?? this.secretKey,
    region: region ?? this.region,
    service: service ?? this.service,
    sessionToken: sessionToken ?? this.sessionToken,
  );

  @override
  String get type => 'awsv4';

  @override
  Map<String, Object?> toJson() => {
    'type': type,
    'accessKey': accessKey,
    'secretKey': secretKey,
    'region': region,
    'service': service,
    if (sessionToken.isNotEmpty) 'sessionToken': sessionToken,
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
