import 'dart:convert';

import 'package:verbnest_core/verbnest_core.dart';

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
    this.refreshToken,
    this.scope,
  });

  final String accessToken;
  final String tokenType;
  final DateTime? expiresAt;
  final String? refreshToken;
  final String? scope;

  bool isFresh(DateTime now, {Duration skew = const Duration(seconds: 30)}) =>
      expiresAt == null || now.add(skew).isBefore(expiresAt!);
}

/// One cached token as shown in the token manager (FR-AUTH-003).
class CachedToken {
  const CachedToken({
    required this.key,
    required this.auth,
    required this.token,
  });

  final String key;
  final OAuth2Auth auth;
  final OAuth2Token token;
}

/// In-memory token cache so a token is reused until it expires (FR-AUTH-002).
/// Tokens are never persisted.
class OAuth2TokenCache {
  final Map<String, CachedToken> _tokens = {};

  /// Identifies the grant independent of anything else about the request.
  static String keyFor(OAuth2Auth a) => [
    a.grant.wire,
    a.authUrl,
    a.tokenUrl,
    a.clientId,
    a.scope,
    a.username,
  ].join('\u0000');

  /// A token that is still valid, or null.
  OAuth2Token? get(OAuth2Auth a, {DateTime? now}) {
    final t = peek(a);
    if (t == null) return null;
    if (t.isFresh(now ?? DateTime.now())) return t;
    // Without a refresh token an expired token is of no further use.
    if (t.refreshToken == null) _tokens.remove(keyFor(a));
    return null;
  }

  /// The cached token even when expired, e.g. to use its refresh token.
  OAuth2Token? peek(OAuth2Auth a) => _tokens[keyFor(a)]?.token;

  void put(OAuth2Auth a, OAuth2Token t) =>
      _tokens[keyFor(a)] = CachedToken(key: keyFor(a), auth: a, token: t);

  void remove(String key) => _tokens.remove(key);

  List<CachedToken> get entries => _tokens.values.toList();

  void clear() => _tokens.clear();
}

/// A token request carries the client secret or user password, so it never
/// follows a redirect to another host.
HttpSettings _noRedirects(HttpSettings s) => HttpSettings(
  httpVersion: s.httpVersion,
  timeout: s.timeout,
  followRedirects: false,
  maxRedirects: s.maxRedirects,
  verifyTls: s.verifyTls,
  autoDecompress: s.autoDecompress,
  keepMethodOnRedirect: s.keepMethodOnRedirect,
  stripAuthCrossOrigin: s.stripAuthCrossOrigin,
  sendCookies: s.sendCookies,
  proxy: s.proxy,
  useSystemProxy: s.useSystemProxy,
  tls: s.tls,
);

Uri _tokenUri(OAuth2Auth auth) {
  try {
    final url = Uri.parse(auth.tokenUrl.trim());
    if (url.host.isEmpty) throw const FormatException('missing host');
    return url;
  } on FormatException {
    throw OAuth2Error('Invalid token URL "${auth.tokenUrl}"');
  }
}

/// Requests a token using a grant that needs no browser. All fields must
/// already have their variables resolved.
Future<OAuth2Token> fetchOAuth2Token(
  HttpEngine engine,
  OAuth2Auth auth, {
  CancelToken? cancel,
  HttpSettings settings = const HttpSettings(),
  DateTime? now,
}) {
  if (auth.interactive) {
    throw const OAuth2Error('This grant needs the browser sign-in');
  }
  return _tokenRequest(
    engine,
    auth,
    {
      'grant_type': auth.grant.wire,
      if (auth.scope.isNotEmpty) 'scope': auth.scope,
      if (auth.grant == OAuth2Grant.password) ...{
        'username': auth.username,
        'password': auth.password,
      },
    },
    cancel: cancel,
    settings: settings,
    now: now,
  );
}

/// Trades the code from the browser for a token (RFC 6749 §4.1.3, with the
/// PKCE verifier from RFC 7636 when one was used).
Future<OAuth2Token> exchangeAuthorizationCode(
  HttpEngine engine,
  OAuth2Auth auth, {
  required String code,
  required String redirectUri,
  String? codeVerifier,
  CancelToken? cancel,
  HttpSettings settings = const HttpSettings(),
  DateTime? now,
}) => _tokenRequest(
  engine,
  auth,
  {
    'grant_type': 'authorization_code',
    'code': code,
    'redirect_uri': redirectUri,
    'code_verifier': ?codeVerifier,
  },
  cancel: cancel,
  settings: settings,
  now: now,
);

/// Gets a new access token with a refresh token (FR-AUTH-003). The old
/// refresh token is kept when the server does not send a new one.
Future<OAuth2Token> refreshOAuth2Token(
  HttpEngine engine,
  OAuth2Auth auth,
  String refreshToken, {
  CancelToken? cancel,
  HttpSettings settings = const HttpSettings(),
  DateTime? now,
}) async {
  final t = await _tokenRequest(
    engine,
    auth,
    {
      'grant_type': 'refresh_token',
      'refresh_token': refreshToken,
      if (auth.scope.isNotEmpty) 'scope': auth.scope,
    },
    cancel: cancel,
    settings: settings,
    now: now,
  );
  return t.refreshToken != null
      ? t
      : OAuth2Token(
          accessToken: t.accessToken,
          tokenType: t.tokenType,
          expiresAt: t.expiresAt,
          refreshToken: refreshToken,
          scope: t.scope,
        );
}

Future<OAuth2Token> _tokenRequest(
  HttpEngine engine,
  OAuth2Auth auth,
  Map<String, String> form, {
  CancelToken? cancel,
  required HttpSettings settings,
  DateTime? now,
}) async {
  final url = _tokenUri(auth);
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
  } else if (form['grant_type'] == 'authorization_code') {
    // A public client sends only its id.
    form['client_id'] = auth.clientId;
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
        settings: _noRedirects(settings),
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
  final refresh = json['refresh_token'];
  return OAuth2Token(
    accessToken: token,
    tokenType: (json['token_type'] as String?) ?? 'Bearer',
    expiresAt: seconds == null
        ? null
        : (now ?? DateTime.now()).add(Duration(seconds: seconds)),
    refreshToken: refresh is String && refresh.isNotEmpty ? refresh : null,
    scope: json['scope'] as String?,
  );
}
