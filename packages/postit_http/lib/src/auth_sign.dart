import 'dart:convert';
import 'dart:math';

import 'package:crypto/crypto.dart';
import 'package:postit_core/postit_core.dart';

import 'models.dart';

String _b64url(List<int> bytes) => base64Url.encode(bytes).replaceAll('=', '');

/// A signed JWT for [auth] (FR-AUTH-004). `iat` (seconds) is added when the
/// payload is a JSON object without one. All text must be variable-resolved.
String signJwt(JwtAuth auth, {DateTime? now}) {
  Object? payload;
  try {
    payload = jsonDecode(auth.payload.trim().isEmpty ? '{}' : auth.payload);
  } on FormatException catch (e) {
    throw FormatException('The JWT payload is not valid JSON: ${e.message}');
  }
  if (payload is! Map) {
    throw const FormatException('The JWT payload must be a JSON object');
  }
  final claims = payload.cast<String, Object?>();
  claims.putIfAbsent(
    'iat',
    () => (now ?? DateTime.now()).millisecondsSinceEpoch ~/ 1000,
  );
  final header = {'alg': auth.algorithm.label, 'typ': 'JWT'};
  final input =
      '${_b64url(utf8.encode(jsonEncode(header)))}.'
      '${_b64url(utf8.encode(jsonEncode(claims)))}';
  final hash = switch (auth.algorithm) {
    JwtAlgorithm.hs256 => sha256,
    JwtAlgorithm.hs384 => sha384,
    JwtAlgorithm.hs512 => sha512,
  };
  final sig = Hmac(hash, utf8.encode(auth.secret)).convert(utf8.encode(input));
  return '$input.${_b64url(sig.bytes)}';
}

// ---- AWS Signature Version 4 ---------------------------------------------

String _hex(List<int> bytes) =>
    bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();

List<int> _hmac(List<int> key, String data) =>
    Hmac(sha256, key).convert(utf8.encode(data)).bytes;

String _awsEncode(String s) {
  final out = StringBuffer();
  for (final b in utf8.encode(s)) {
    final c = String.fromCharCode(b);
    if (RegExp(r'[A-Za-z0-9\-_.~]').hasMatch(c)) {
      out.write(c);
    } else {
      out.write('%${b.toRadixString(16).toUpperCase().padLeft(2, '0')}');
    }
  }
  return out.toString();
}

/// The headers to add so the request carries a SigV4 signature: `X-Amz-Date`,
/// `X-Amz-Security-Token` (if set) and `Authorization`. Signs `host`,
/// `x-amz-date`, the token and an existing `content-type`.
List<Header> signAwsV4(
  AwsV4Auth auth, {
  required String method,
  required Uri url,
  required List<Header> headers,
  required List<int> body,
  DateTime? now,
}) {
  final t = (now ?? DateTime.now()).toUtc();
  String two(int n) => n.toString().padLeft(2, '0');
  final date =
      '${t.year.toString().padLeft(4, '0')}${two(t.month)}${two(t.day)}';
  final stamp = '${date}T${two(t.hour)}${two(t.minute)}${two(t.second)}Z';

  final defaultPort = url.scheme == 'https' ? 443 : 80;
  final host = url.hasPort && url.port != defaultPort
      ? '${url.host}:${url.port}'
      : url.host;
  final contentType = headers
      .where((h) => h.$1.toLowerCase() == 'content-type')
      .map((h) => h.$2.trim())
      .firstOrNull;

  final signed = <String, String>{
    'host': host,
    'content-type': ?contentType,
    'x-amz-date': stamp,
    if (auth.sessionToken.isNotEmpty) 'x-amz-security-token': auth.sessionToken,
  };
  final names = signed.keys.toList()..sort();
  final canonicalHeaders = [for (final n in names) '$n:${signed[n]}\n'].join();
  final signedHeaders = names.join(';');

  // Services other than S3 encode the path twice.
  var path = url.path.isEmpty ? '/' : url.path;
  if (auth.service != 's3') path = path.replaceAll('%', '%25');

  final pairs = <(String, String)>[];
  if (url.query.isNotEmpty) {
    for (final part in url.query.split('&')) {
      if (part.isEmpty) continue;
      final eq = part.indexOf('=');
      final k = eq < 0 ? part : part.substring(0, eq);
      final v = eq < 0 ? '' : part.substring(eq + 1);
      pairs.add((
        _awsEncode(Uri.decodeQueryComponent(k)),
        _awsEncode(Uri.decodeQueryComponent(v)),
      ));
    }
  }
  pairs.sort(
    (a, b) => a.$1 == b.$1 ? a.$2.compareTo(b.$2) : a.$1.compareTo(b.$1),
  );
  final query = pairs.map((p) => '${p.$1}=${p.$2}').join('&');

  final payloadHash = _hex(sha256.convert(body).bytes);
  final canonical = [
    method.toUpperCase(),
    path,
    query,
    canonicalHeaders,
    signedHeaders,
    payloadHash,
  ].join('\n');

  final scope = '$date/${auth.region}/${auth.service}/aws4_request';
  final toSign = [
    'AWS4-HMAC-SHA256',
    stamp,
    scope,
    _hex(sha256.convert(utf8.encode(canonical)).bytes),
  ].join('\n');

  var key = _hmac(utf8.encode('AWS4${auth.secretKey}'), date);
  key = _hmac(key, auth.region);
  key = _hmac(key, auth.service);
  key = _hmac(key, 'aws4_request');
  final signature = _hex(_hmac(key, toSign));

  return [
    ('X-Amz-Date', stamp),
    if (auth.sessionToken.isNotEmpty)
      ('X-Amz-Security-Token', auth.sessionToken),
    (
      'Authorization',
      'AWS4-HMAC-SHA256 Credential=${auth.accessKey}/$scope, '
          'SignedHeaders=$signedHeaders, Signature=$signature',
    ),
  ];
}

// ---- HTTP Digest -----------------------------------------------------------

/// A parsed `WWW-Authenticate: Digest ...` challenge.
class DigestChallenge {
  DigestChallenge(this.params);

  final Map<String, String> params;

  String get realm => params['realm'] ?? '';
  String get nonce => params['nonce'] ?? '';
  String? get opaque => params['opaque'];
  String get algorithm => params['algorithm'] ?? 'MD5';
  List<String> get qop => (params['qop'] ?? '')
      .split(',')
      .map((q) => q.trim())
      .where((q) => q.isNotEmpty)
      .toList();

  /// The first Digest challenge among [values] (one per header line), or
  /// null. Other schemes in the same line are ignored.
  static DigestChallenge? find(Iterable<String> values) {
    for (final v in values) {
      final m = RegExp(r'digest\s+(.*)$', caseSensitive: false).firstMatch(v);
      if (m == null) continue;
      final params = <String, String>{};
      for (final p in RegExp(
        r'([A-Za-z0-9_-]+)\s*=\s*("((?:[^"\\]|\\.)*)"|[^,\s]*)',
      ).allMatches(m[1]!)) {
        params[p[1]!.toLowerCase()] = p[3] != null
            ? p[3]!.replaceAllMapped(RegExp(r'\\(.)'), (e) => e[1]!)
            : p[2]!;
      }
      if (params.containsKey('nonce')) return DigestChallenge(params);
    }
    return null;
  }
}

/// The `Authorization` value answering [challenge] (RFC 7616). [uri] is the
/// request target (path and query). [cnonce] and [nonceCount] are injectable
/// for tests.
String digestAuthorization(
  DigestChallenge challenge,
  DigestAuth auth, {
  required String method,
  required String uri,
  List<int> body = const [],
  String? cnonce,
  int nonceCount = 1,
}) {
  final algo = challenge.algorithm.toUpperCase();
  final session = algo.endsWith('-SESS');
  final Hash hash = algo.startsWith('SHA-256') ? sha256 : md5;
  String h(String s) => _hex(hash.convert(utf8.encode(s)).bytes);

  final qops = challenge.qop;
  final qop = qops.contains('auth')
      ? 'auth'
      : (qops.contains('auth-int') ? 'auth-int' : null);
  final nc = nonceCount.toRadixString(16).padLeft(8, '0');
  final cn =
      cnonce ?? _hex(List.generate(8, (_) => Random.secure().nextInt(256)));

  var ha1 = h('${auth.username}:${challenge.realm}:${auth.password}');
  if (session) ha1 = h('$ha1:${challenge.nonce}:$cn');
  final bodyHash = _hex(hash.convert(body).bytes);
  final ha2 = qop == 'auth-int'
      ? h('${method.toUpperCase()}:$uri:$bodyHash')
      : h('${method.toUpperCase()}:$uri');
  final response = qop == null
      ? h('$ha1:${challenge.nonce}:$ha2')
      : h('$ha1:${challenge.nonce}:$nc:$cn:$qop:$ha2');

  String q(String s) => '"${s.replaceAll(r'\', r'\\').replaceAll('"', r'\"')}"';
  return [
    'Digest username=${q(auth.username)}',
    'realm=${q(challenge.realm)}',
    'nonce=${q(challenge.nonce)}',
    'uri=${q(uri)}',
    if (challenge.params.containsKey('algorithm'))
      'algorithm=${challenge.algorithm}',
    'response=${q(response)}',
    if (qop != null) ...['qop=$qop', 'nc=$nc', 'cnonce=${q(cn)}'],
    if (challenge.opaque != null) 'opaque=${q(challenge.opaque!)}',
  ].join(', ');
}
