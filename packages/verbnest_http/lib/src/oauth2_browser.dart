import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:crypto/crypto.dart';
import 'package:verbnest_core/verbnest_core.dart';

import 'engine.dart';
import 'models.dart';
import 'oauth2.dart';

/// PKCE verifier and its S256 challenge (RFC 7636).
class PkcePair {
  const PkcePair(this.verifier, this.challenge);

  final String verifier;
  final String challenge;

  factory PkcePair.generate([Random? random]) {
    final r = random ?? Random.secure();
    final verifier = base64Url
        .encode(List.generate(32, (_) => r.nextInt(256)))
        .replaceAll('=', '');
    return PkcePair(verifier, challengeFor(verifier));
  }

  static String challengeFor(String verifier) => base64Url
      .encode(sha256.convert(ascii.encode(verifier)).bytes)
      .replaceAll('=', '');
}

/// The page the user signs in on, with the standard query added to any
/// query the configured URL already has.
Uri buildAuthorizeUrl(
  OAuth2Auth auth, {
  required String redirectUri,
  required String state,
  String? codeChallenge,
}) {
  final base = Uri.parse(auth.authUrl.trim());
  if (base.host.isEmpty || (base.scheme != 'http' && base.scheme != 'https')) {
    throw OAuth2Error('Invalid authorization URL "${auth.authUrl}"');
  }
  return base.replace(
    queryParameters: {
      ...base.queryParameters,
      'response_type': auth.grant == OAuth2Grant.implicit ? 'token' : 'code',
      'client_id': auth.clientId,
      'redirect_uri': redirectUri,
      if (auth.scope.isNotEmpty) 'scope': auth.scope,
      'state': state,
      if (codeChallenge != null) ...{
        'code_challenge': codeChallenge,
        'code_challenge_method': 'S256',
      },
    },
  );
}

/// Receives the browser redirect on `http://127.0.0.1:<random>/callback`
/// (FR-AUTH-003). The implicit flow returns its token in the URL fragment,
/// which browsers do not send, so the first page forwards it as a query.
class LoopbackReceiver {
  LoopbackReceiver._(this._server, this._state) {
    _server.listen(_handle);
  }

  final HttpServer _server;

  /// Only a redirect carrying this `state` ends the wait, so another local
  /// program or web page cannot cancel or feed the sign-in.
  final String? _state;
  final _done = Completer<Map<String, String>>();

  static Future<LoopbackReceiver> start({String? state}) async =>
      LoopbackReceiver._(
        await HttpServer.bind(InternetAddress.loopbackIPv4, 0),
        state,
      );

  String get redirectUri => 'http://127.0.0.1:${_server.port}/callback';

  static const _forward =
      '''<!doctype html><meta charset="utf-8"><title>Verbnest</title>
<body><p id="m">Finishing sign-in…</p>
<script>
var h = location.hash.slice(1);
if (h) { location.replace('/callback?' + h); }
else { document.getElementById('m').textContent = 'No sign-in response was received.'; }
</script></body>''';

  static const _finished =
      '''<!doctype html><meta charset="utf-8"><title>Verbnest</title>
<body><p>Signed in. You can close this tab and return to Verbnest.</p></body>''';

  void _handle(HttpRequest req) {
    final q = req.uri.queryParameters;
    final meaningful =
        q.containsKey('code') ||
        q.containsKey('error') ||
        q.containsKey('access_token');
    req.response.headers.contentType = ContentType.html;
    if (req.uri.path != '/callback') {
      req.response.statusCode = 404;
      req.response.close();
      return;
    }
    if (meaningful && _state != null && q['state'] != _state) {
      req.response.statusCode = 400;
      req.response.write('Unexpected sign-in response.');
    } else if (meaningful) {
      if (!_done.isCompleted) _done.complete(q);
      req.response.write(_finished);
    } else {
      req.response.write(_forward);
    }
    req.response.close();
  }

  /// The redirect parameters, or an [OAuth2Error] on timeout or cancel.
  Future<Map<String, String>> result({
    required Duration timeout,
    CancelToken? cancel,
  }) {
    final timer = Timer(timeout, () {
      if (!_done.isCompleted) {
        _done.completeError(const OAuth2Error('Sign-in timed out'));
      }
    });
    final poll = Timer.periodic(const Duration(milliseconds: 200), (_) {
      if (cancel?.isCancelled == true && !_done.isCompleted) {
        _done.completeError(const OAuth2Error('Sign-in cancelled'));
      }
    });
    return _done.future.whenComplete(() {
      timer.cancel();
      poll.cancel();
    });
  }

  /// Stops listening at once but lets the page already being sent finish,
  /// so the browser sees the "you can close this tab" message.
  Future<void> close() {
    _server.idleTimeout = const Duration(seconds: 1);
    return _server
        .close()
        .then<void>((_) {})
        .timeout(
          const Duration(seconds: 2),
          onTimeout: () => _server.close(force: true).then<void>((_) {}),
        );
  }
}

/// Signs in with the system browser: opens the authorization page through
/// [openUrl], waits for the redirect, and returns the token (code + PKCE or
/// implicit). Fields of [auth] must already have their variables resolved.
Future<OAuth2Token> authorizeInBrowser(
  HttpEngine engine,
  OAuth2Auth auth, {
  required Future<void> Function(Uri url) openUrl,
  CancelToken? cancel,
  HttpSettings settings = const HttpSettings(),
  Duration timeout = const Duration(minutes: 5),
  DateTime? now,
  Random? random,
}) async {
  final r = random ?? Random.secure();
  final state = List.generate(
    16,
    (_) => r.nextInt(256).toRadixString(16).padLeft(2, '0'),
  ).join();
  final pkce = auth.grant == OAuth2Grant.authorizationCode && auth.usePkce
      ? PkcePair.generate(r)
      : null;
  final receiver = await LoopbackReceiver.start(state: state);
  try {
    final url = buildAuthorizeUrl(
      auth,
      redirectUri: receiver.redirectUri,
      state: state,
      codeChallenge: pkce?.challenge,
    );
    final wait = receiver.result(timeout: timeout, cancel: cancel);
    // A failure to open the browser must not leave `wait` unhandled.
    unawaited(wait.then<void>((_) {}, onError: (_) {}));
    try {
      await openUrl(url);
    } on Object catch (e) {
      throw OAuth2Error('Could not open the browser: $e');
    }
    final params = await wait;
    if (params['error'] != null) {
      final detail = params['error_description'];
      throw OAuth2Error(
        'Sign-in failed: ${params['error']}${detail == null ? '' : ' ($detail)'}',
      );
    }
    if (params['state'] != state) {
      throw const OAuth2Error(
        'Sign-in response had the wrong state value; it was ignored',
      );
    }
    if (auth.grant == OAuth2Grant.implicit) {
      final token = params['access_token'];
      if (token == null || token.isEmpty) {
        throw const OAuth2Error('Sign-in response has no access_token');
      }
      final seconds = int.tryParse(params['expires_in'] ?? '');
      return OAuth2Token(
        accessToken: token,
        tokenType: params['token_type'] ?? 'Bearer',
        expiresAt: seconds == null
            ? null
            : (now ?? DateTime.now()).add(Duration(seconds: seconds)),
        scope: params['scope'],
      );
    }
    final code = params['code'];
    if (code == null || code.isEmpty) {
      throw const OAuth2Error('Sign-in response has no code');
    }
    return await exchangeAuthorizationCode(
      engine,
      auth,
      code: code,
      redirectUri: receiver.redirectUri,
      codeVerifier: pkce?.verifier,
      cancel: cancel,
      settings: settings,
      now: now,
    );
  } finally {
    await receiver.close();
  }
}
