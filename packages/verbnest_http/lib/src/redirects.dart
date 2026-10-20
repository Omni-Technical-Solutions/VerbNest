import 'models.dart';

/// The request to send after [r], or null when [r] is not a redirect to
/// follow. Credentials never cross origins (security review, redirects).
HttpRequestSpec? nextHop(HttpRequestSpec spec, HttpResponseRecord r) {
  final s = spec.settings;
  if (!s.followRedirects ||
      !const {301, 302, 303, 307, 308}.contains(r.status)) {
    return null;
  }
  final location = r.header('location');
  if (location == null) return null;
  final target = spec.url.resolve(location);
  final switchToGet =
      !s.keepMethodOnRedirect &&
      (r.status == 303 ||
          ((r.status == 301 || r.status == 302) && spec.method != 'HEAD'));
  final crossOrigin = _origin(target) != _origin(spec.url);
  final stripped = crossOrigin && s.stripAuthCrossOrigin;
  return HttpRequestSpec(
    method: switchToGet ? 'GET' : spec.method,
    url: target,
    headers: [
      for (final h in spec.headers)
        if (!_dropOnRedirect(h.$1, switchToGet, crossOrigin, stripped)) h,
    ],
    body: switchToGet ? null : spec.body,
    settings: s,
  );
}

bool _dropOnRedirect(
  String name,
  bool switchToGet,
  bool crossOrigin,
  bool stripAuth,
) {
  final n = name.toLowerCase();
  if (n == 'host') return true;
  if (switchToGet && (n == 'content-length' || n == 'content-type')) {
    return true;
  }
  // Even when a request opts out of stripping (stripAuthCrossOrigin: false),
  // the common credential carriers never cross origins: imported requests
  // could otherwise flip the flag and arrange a credential leak.
  if (crossOrigin &&
      (n == 'authorization' || n == 'proxy-authorization' || n == 'cookie')) {
    return true;
  }
  return stripAuth && _looksLikeCredential(n);
}

/// Headers that may follow a redirect to another origin. Anything else,
/// including custom names that carry secrets, is dropped: a denylist cannot
/// know every credential header.
const _crossOriginSafe = {
  'accept',
  'accept-encoding',
  'accept-language',
  'cache-control',
  'content-length',
  'content-type',
  'user-agent',
  'pragma',
  'origin',
  'referer',
};

bool _looksLikeCredential(String lowerName) =>
    !_crossOriginSafe.contains(lowerName);

String _origin(Uri u) => '${u.scheme}://${u.host}:${u.port}';
