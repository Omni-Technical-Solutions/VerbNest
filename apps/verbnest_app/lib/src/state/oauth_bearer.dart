import 'package:verbnest_core/verbnest_core.dart';
import 'package:verbnest_http/verbnest_http.dart';

import 'browser_port.dart';

/// A bearer token for [auth], from the cache or the token endpoint. A stale
/// token is refreshed when it has a refresh token; otherwise the user signs
/// in again (interactive) or the client credentials are sent.
Future<Auth> oauthBearer({
  required HttpEngine engine,
  required OAuth2TokenCache cache,
  required BrowserOpener openUrl,
  required OAuth2Auth auth,
  required VariableResolver resolver,
  required HttpSettings defaults,
  required CancelToken cancel,
}) async {
  final resolved = auth.mapText((t) => resolver.resolve(t).value);
  var token = cache.get(resolved);
  if (token == null) {
    token =
        await _refreshed(engine, cache, resolved, defaults, cancel) ??
        (resolved.interactive
            ? await authorizeInBrowser(
                engine,
                resolved,
                openUrl: openUrl,
                cancel: cancel,
                settings: defaults,
              )
            : await fetchOAuth2Token(
                engine,
                resolved,
                cancel: cancel,
                settings: defaults,
              ));
    cache.put(resolved, token);
  }
  return BearerAuth(token: token.accessToken);
}

Future<OAuth2Token?> _refreshed(
  HttpEngine engine,
  OAuth2TokenCache cache,
  OAuth2Auth resolved,
  HttpSettings defaults,
  CancelToken cancel,
) async {
  final refresh = cache.peek(resolved)?.refreshToken;
  if (refresh == null) return null;
  try {
    return await refreshOAuth2Token(
      engine,
      resolved,
      refresh,
      cancel: cancel,
      settings: defaults,
    );
  } on OAuth2Error {
    // The refresh token was refused; sign in again.
    return null;
  }
}
