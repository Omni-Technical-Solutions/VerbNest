/// A cookie held by the jar (FR-HTTP-011).
class StoredCookie {
  const StoredCookie({
    required this.name,
    required this.value,
    required this.domain,
    this.path = '/',
    this.expires,
    this.secure = false,
    this.httpOnly = false,
    this.hostOnly = true,
    this.sameSite,
    required this.createdAt,
  });

  final String name;
  final String value;

  /// Lower case, no leading dot.
  final String domain;
  final String path;

  /// Null for a session cookie (kept until the jar is cleared).
  final DateTime? expires;
  final bool secure;
  final bool httpOnly;

  /// Sent only to [domain] itself, not to its subdomains.
  final bool hostOnly;
  final String? sameSite;
  final DateTime createdAt;

  bool isExpired(DateTime now) => expires != null && !expires!.isAfter(now);

  String get id => '$domain\u0000$path\u0000$name';

  Map<String, Object?> toJson() => {
    'name': name,
    'value': value,
    'domain': domain,
    'path': path,
    if (expires != null) 'expires': expires!.toUtc().toIso8601String(),
    if (secure) 'secure': true,
    if (httpOnly) 'httpOnly': true,
    if (!hostOnly) 'hostOnly': false,
    if (sameSite != null) 'sameSite': sameSite,
    'createdAt': createdAt.toUtc().toIso8601String(),
  };

  static StoredCookie? fromJson(Object? j) {
    if (j is! Map) return null;
    final name = j['name'];
    final domain = j['domain'];
    if (name is! String || domain is! String) return null;
    return StoredCookie(
      name: name,
      value: j['value'] as String? ?? '',
      domain: domain,
      path: j['path'] as String? ?? '/',
      expires: j['expires'] is String
          ? DateTime.tryParse(j['expires'] as String)
          : null,
      secure: j['secure'] as bool? ?? false,
      httpOnly: j['httpOnly'] as bool? ?? false,
      hostOnly: j['hostOnly'] as bool? ?? true,
      sameSite: j['sameSite'] as String?,
      createdAt:
          DateTime.tryParse(j['createdAt'] as String? ?? '') ?? DateTime.now(),
    );
  }
}

/// Stores `Set-Cookie` responses and builds `Cookie` request headers
/// (RFC 6265). Not handled: the public suffix list, so a site can set a
/// cookie for a shared suffix such as `co.uk`; `SameSite` is kept but not
/// enforced, because VerbNest is not a browser.
class CookieJar {
  CookieJar([Iterable<StoredCookie> initial = const []]) {
    for (final c in initial) {
      _cookies[c.id] = c;
    }
  }

  final Map<String, StoredCookie> _cookies = {};

  /// Called after the jar changed, e.g. to save it.
  void Function()? onChanged;

  List<StoredCookie> get cookies {
    final list = _cookies.values.toList()
      ..sort((a, b) {
        final d = a.domain.compareTo(b.domain);
        return d != 0 ? d : a.name.compareTo(b.name);
      });
    return list;
  }

  bool get isEmpty => _cookies.isEmpty;

  void remove(StoredCookie c) {
    if (_cookies.remove(c.id) != null) onChanged?.call();
  }

  void removeDomain(String domain) {
    final before = _cookies.length;
    _cookies.removeWhere((_, c) => c.domain == domain);
    if (_cookies.length != before) onChanged?.call();
  }

  void clear() {
    if (_cookies.isEmpty) return;
    _cookies.clear();
    onChanged?.call();
  }

  void set(StoredCookie c) {
    _cookies[c.id] = c;
    onChanged?.call();
  }

  /// Saves what the response to [url] asked to store. Invalid cookies are
  /// ignored. Returns how many were stored or deleted.
  int storeFromResponse(
    Uri url,
    Iterable<String> setCookieHeaders, {
    DateTime? now,
  }) {
    final at = now ?? DateTime.now();
    var changed = 0;
    for (final h in setCookieHeaders) {
      final c = _parse(url, h, at);
      if (c == null) continue;
      if (c.expires != null && !c.expires!.isAfter(at)) {
        if (_cookies.remove(c.id) != null) changed++;
        continue;
      }
      final old = _cookies[c.id];
      // A plain-HTTP response must not overwrite a Secure cookie.
      if (old != null &&
          old.secure &&
          !c.secure &&
          url.scheme != 'https' &&
          !_isLoopback(url.host)) {
        continue;
      }
      _cookies[c.id] = old == null
          ? c
          : StoredCookie(
              name: c.name,
              value: c.value,
              domain: c.domain,
              path: c.path,
              expires: c.expires,
              secure: c.secure,
              httpOnly: c.httpOnly,
              hostOnly: c.hostOnly,
              sameSite: c.sameSite,
              createdAt: old.createdAt,
            );
      changed++;
    }
    if (changed > 0) onChanged?.call();
    return changed;
  }

  /// Cookies that apply to [url], in the order a `Cookie` header lists them.
  List<StoredCookie> matching(Uri url, {DateTime? now}) {
    final at = now ?? DateTime.now();
    final host = url.host.toLowerCase();
    final path = url.path.isEmpty ? '/' : url.path;
    final secureOk = url.scheme == 'https' || _isLoopback(host);
    final out = [
      for (final c in _cookies.values)
        if (!c.isExpired(at) &&
            _domainMatches(host, c) &&
            _pathMatches(path, c.path) &&
            (!c.secure || secureOk))
          c,
    ];
    out.sort((a, b) {
      final p = b.path.length.compareTo(a.path.length);
      return p != 0 ? p : a.createdAt.compareTo(b.createdAt);
    });
    return out;
  }

  /// The `Cookie` header value for [url], or null when nothing applies.
  String? cookieHeader(Uri url, {DateTime? now}) {
    final list = matching(url, now: now);
    if (list.isEmpty) return null;
    return list.map((c) => '${c.name}=${c.value}').join('; ');
  }

  Map<String, Object?> toJson() => {
    'cookies': [for (final c in cookies) c.toJson()],
  };

  factory CookieJar.fromJson(Object? json) => CookieJar([
    if (json is Map && json['cookies'] is List)
      for (final c in json['cookies'] as List) ?StoredCookie.fromJson(c),
  ]);

  // ---- parsing ----

  StoredCookie? _parse(Uri url, String header, DateTime now) {
    final parts = header.split(';');
    final pair = _nameValue(parts.first);
    if (pair == null) return null;
    final (name, value) = pair;
    final attrs = _Attributes.read(parts.skip(1));
    final domainAttr = attrs.domain;
    final pathAttr = attrs.path;
    final expires = attrs.expires;
    final maxAge = attrs.maxAge;
    final secure = attrs.secure;
    final httpOnly = attrs.httpOnly;
    final sameSite = attrs.sameSite;

    final host = url.host.toLowerCase();
    if (host.isEmpty) return null;
    if (secure && url.scheme != 'https' && !_isLoopback(host)) return null;

    final scope = _scopeFor(host, domainAttr);
    if (scope == null) return null;
    final (domain, hostOnly) = scope;

    final path = pathAttr != null && pathAttr.startsWith('/')
        ? pathAttr
        : _defaultPath(url.path);

    DateTime? exp = expires;
    if (maxAge != null) {
      exp = maxAge <= 0
          ? DateTime.fromMillisecondsSinceEpoch(0, isUtc: true)
          : now.add(Duration(seconds: maxAge.clamp(1, 400 * 86400)));
    }

    return StoredCookie(
      name: name,
      value: value,
      domain: domain,
      path: path,
      expires: exp,
      secure: secure,
      httpOnly: httpOnly,
      hostOnly: hostOnly,
      sameSite: sameSite,
      createdAt: now,
    );
  }

  /// The name and value of the first `name=value` part, or null when it is
  /// not a usable cookie.
  static (String, String)? _nameValue(String first) {
    final eq = first.indexOf('=');
    if (eq <= 0) return null;
    final name = first.substring(0, eq).trim();
    if (name.isEmpty) return null;
    final value = first.substring(eq + 1).trim();
    // Control characters would split the Cookie header or a log line, and
    // browsers cap a cookie at 4096 bytes.
    if (_control.hasMatch(name) ||
        _control.hasMatch(value) ||
        name.length + value.length > 4096) {
      return null;
    }
    return (name, value);
  }

  /// The cookie's domain and whether it is host-only, or null when [host] may
  /// not set a cookie for [domainAttr].
  (String, bool)? _scopeFor(String host, String? domainAttr) {
    if (domainAttr == null || domainAttr.isEmpty) return (host, true);
    final ok =
        host == domainAttr ||
        (!_isIp(host) &&
            host.endsWith('.$domainAttr') &&
            domainAttr.contains('.') &&
            !_publicSuffixes.contains(domainAttr));
    return ok ? (domainAttr, false) : null;
  }

  static final _control = RegExp(r'[\x00-\x1f\x7f]');

  /// Multi-label public suffixes a site must not set cookies for. This is a
  /// short list of the common ones, not the full Public Suffix List.
  static const _publicSuffixes = {
    'co.uk',
    'org.uk',
    'ac.uk',
    'gov.uk',
    'com.au',
    'net.au',
    'org.au',
    'co.jp',
    'co.nz',
    'co.in',
    'com.br',
    'com.cn',
    'co.za',
    'github.io',
    'herokuapp.com',
    'appspot.com',
    'cloudfront.net',
    'blogspot.com',
    'azurewebsites.net',
    'vercel.app',
    'netlify.app',
    'pages.dev',
  };

  static String _defaultPath(String requestPath) {
    if (!requestPath.startsWith('/')) return '/';
    final i = requestPath.lastIndexOf('/');
    return i <= 0 ? '/' : requestPath.substring(0, i);
  }

  static bool _domainMatches(String host, StoredCookie c) {
    if (c.hostOnly) return host == c.domain;
    return host == c.domain || host.endsWith('.${c.domain}');
  }

  static bool _pathMatches(String requestPath, String cookiePath) {
    if (requestPath == cookiePath) return true;
    if (!requestPath.startsWith(cookiePath)) return false;
    return cookiePath.endsWith('/') || requestPath[cookiePath.length] == '/';
  }

  static bool _isIp(String host) =>
      host.contains(':') || RegExp(r'^\d+\.\d+\.\d+\.\d+$').hasMatch(host);

  static bool _isLoopback(String host) =>
      host == 'localhost' ||
      host == '127.0.0.1' ||
      host == '::1' ||
      host == '[::1]';
}

const _months = [
  'jan', 'feb', 'mar', 'apr', 'may', 'jun', //
  'jul', 'aug', 'sep', 'oct', 'nov', 'dec',
];

/// Parses the date formats servers use in `Expires` (RFC 6265 §5.1.1, the
/// common forms): `Wed, 21 Oct 2015 07:28:00 GMT`, `Wed, 21-Oct-15 07:28:00
/// GMT`, `Wed Oct 21 07:28:00 2015`. Returns null when it cannot tell.
DateTime? parseCookieDate(String text) {
  final time = RegExp(r'(\d{1,2}):(\d{2}):(\d{2})').firstMatch(text);
  if (time == null) return null;
  int? month;
  for (final m in RegExp(r'[A-Za-z]{3}').allMatches(text)) {
    final i = _months.indexOf(m[0]!.toLowerCase());
    if (i != -1) {
      month = i + 1;
      break;
    }
  }
  if (month == null) return null;
  final rest = text.replaceFirst(time[0]!, ' ');
  final numbers = RegExp(r'\d+').allMatches(rest).map((m) => m[0]!).toList();
  int? day;
  int? year;
  for (final n in numbers) {
    if (day == null && n.length <= 2) {
      day = int.parse(n);
    } else if (year == null && (n.length == 2 || n.length == 4)) {
      year = int.parse(n);
    }
  }
  if (day == null || year == null) return null;
  if (year < 70) {
    year += 2000;
  } else if (year < 100) {
    year += 1900;
  }
  if (day < 1 || day > 31) return null;
  return DateTime.utc(
    year,
    month,
    day,
    int.parse(time[1]!),
    int.parse(time[2]!),
    int.parse(time[3]!),
  );
}

/// The attributes after the first part of a Set-Cookie header.
class _Attributes {
  String? domain;
  String? path;
  DateTime? expires;
  int? maxAge;
  bool secure = false;
  bool httpOnly = false;
  String? sameSite;

  _Attributes.read(Iterable<String> parts) {
    for (final raw in parts) {
      final t = raw.trim();
      if (t.isEmpty) continue;
      final i = t.indexOf('=');
      final key = (i == -1 ? t : t.substring(0, i)).trim().toLowerCase();
      final val = i == -1 ? '' : t.substring(i + 1).trim();
      _set(key, val);
    }
  }

  void _set(String key, String val) {
    switch (key) {
      case 'domain':
        domain = val.toLowerCase().replaceFirst(RegExp(r'^\.'), '');
      case 'path':
        path = val;
      case 'expires':
        expires = parseCookieDate(val);
      case 'max-age':
        maxAge = int.tryParse(val);
      case 'secure':
        secure = true;
      case 'httponly':
        httpOnly = true;
      case 'samesite':
        sameSite = val;
    }
  }
}
