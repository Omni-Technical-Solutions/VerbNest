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

/// An auth type this version does not understand (e.g. oauth2 before it is
/// implemented). Kept verbatim.
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
