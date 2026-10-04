import 'dart:convert';

import 'package:postit_core/postit_core.dart';

import 'engine.dart';
import 'errors.dart';
import 'models.dart';

/// The token endpoint refused the request or answered with something that is
/// not a token.
class OAuth2Error implements Exception {
  const OAuth2Error(this.message);

  final String message;

  @override
  String toString() => message;
}

class OAuth2Token {
  const OAuth2Token({
    required this.accessToken,
    this.tokenType = 'Bearer',
    this.expiresAt,
  });

  final String accessToken;
  final String tokenType;
  final DateTime? expiresAt;

  bool isFresh(DateTime now, {Duration skew = const Duration(seconds: 30)}) =>
      expiresAt == null || now.add(skew).isBefore(expiresAt!);
}

/// In-memory token cache so a token is reused until it expires (FR-AUTH-002).
/// Tokens are never persisted.
class OAuth2TokenCache {
  final Map<String, OAuth2Token> _tokens = {};

  /// Identifies the grant independent of anything else about the request.
  static String keyFor(OAuth2Auth a) => [
    a.grant.wire,
    a.tokenUrl,
    a.clientId,
    a.scope,
    a.username,
  ].join('\u0000');

  OAuth2Token? get(OAuth2Auth a, {DateTime? now}) {
    final t = _tokens[keyFor(a)];
    if (t == null) return null;
    if (t.isFresh(now ?? DateTime.now())) return t;
    _tokens.remove(keyFor(a));
    return null;
  }

  void put(OAuth2Auth a, OAuth2Token t) => _tokens[keyFor(a)] = t;

  void clear() => _tokens.clear();
}

/// Requests a token using the grant in [auth]. All fields must already have
/// their variables resolved.
Future<OAuth2Token> fetchOAuth2Token(
  HttpEngine engine,
  OAuth2Auth auth, {
  CancelToken? cancel,
  HttpSettings settings = const HttpSettings(),
  DateTime? now,
}) async {
  final Uri url;
  try {
    url = Uri.parse(auth.tokenUrl.trim());
    if (url.host.isEmpty) throw const FormatException('missing host');
  } on FormatException {
    throw OAuth2Error('Invalid token URL "${auth.tokenUrl}"');
  }

  final form = <String, String>{
    'grant_type': auth.grant.wire,
    if (auth.scope.isNotEmpty) 'scope': auth.scope,
    if (auth.grant == OAuth2Grant.password) ...{
      'username': auth.username,
      'password': auth.password,
    },
  };
  final headers = <Header>[
    ('Content-Type', 'application/x-www-form-urlencoded'),
    ('Accept', 'application/json'),
  ];
  if (auth.clientAuthInBody) {
    form['client_id'] = auth.clientId;
    if (auth.clientSecret.isNotEmpty) form['client_secret'] = auth.clientSecret;
  } else if (auth.clientId.isNotEmpty) {
    // RFC 6749 §2.3.1: credentials are form-urlencoded before Basic encoding.
    final id = Uri.encodeQueryComponent(auth.clientId);
    final secret = Uri.encodeQueryComponent(auth.clientSecret);
    headers.add((
      'Authorization',
      'Basic ${base64Encode(utf8.encode('$id:$secret'))}',
    ));
  }

  final body = form.entries
      .map(
        (e) =>
            '${Uri.encodeQueryComponent(e.key)}=${Uri.encodeQueryComponent(e.value)}',
      )
      .join('&');

  final HttpResponseRecord response;
  try {
    response = await engine.send(
      HttpRequestSpec(
        method: 'POST',
        url: url,
        headers: headers,
        body: utf8.encode(body),
        settings: settings,
      ),
      cancel: cancel,
    );
  } on HttpEngineError catch (e) {
    throw OAuth2Error('Token request failed: ${e.message}');
  }

  Map<String, Object?> json;
  try {
    json = (jsonDecode(response.bodyText) as Map).cast<String, Object?>();
  } on Object {
    json = const {};
  }

  if (response.status < 200 || response.status >= 300) {
    final detail = json['error_description'] ?? json['error'];
    throw OAuth2Error(
      'Token request failed: ${response.status} ${response.reason}'
      '${detail == null ? '' : ' ($detail)'}',
    );
  }
  final token = json['access_token'];
  if (token is! String || token.isEmpty) {
    throw const OAuth2Error('Token response has no access_token');
  }
  final expires = json['expires_in'];
  final seconds = expires is num
      ? expires.toInt()
      : int.tryParse('${expires ?? ''}');
  return OAuth2Token(
    accessToken: token,
    tokenType: (json['token_type'] as String?) ?? 'Bearer',
    expiresAt: seconds == null
        ? null
        : (now ?? DateTime.now()).add(Duration(seconds: seconds)),
  );
}
