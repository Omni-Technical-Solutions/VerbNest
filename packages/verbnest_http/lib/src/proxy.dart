enum ProxyKind { http, socks5 }

/// A manual proxy (FR-HTTP-012). An `http` proxy serves plain `http://`
/// requests directly and `https://` ones through a CONNECT tunnel. The
/// connection to the proxy itself is not encrypted.
class ProxyConfig {
  const ProxyConfig({
    required this.kind,
    required this.host,
    required this.port,
    this.username = '',
    this.password = '',
    this.bypass = const [],
  });

  final ProxyKind kind;
  final String host;
  final int port;
  final String username;
  final String password;

  /// Hosts that skip the proxy: `example.com` (and its subdomains),
  /// `*.example.com`, `.example.com`, `localhost`, an IP address, or `*`.
  final List<String> bypass;

  bool get hasAuth => username.isNotEmpty;

  bool bypasses(String targetHost) {
    final h = targetHost.toLowerCase();
    for (final raw in bypass) {
      final p = raw.trim().toLowerCase();
      if (p.isEmpty) continue;
      if (p == '*') return true;
      final suffix = p.startsWith('*.')
          ? p.substring(2)
          : (p.startsWith('.') ? p.substring(1) : p);
      if (h == suffix || h.endsWith('.$suffix')) return true;
    }
    return false;
  }

  ProxyConfig copyWith({
    ProxyKind? kind,
    String? host,
    int? port,
    String? username,
    String? password,
    List<String>? bypass,
  }) => ProxyConfig(
    kind: kind ?? this.kind,
    host: host ?? this.host,
    port: port ?? this.port,
    username: username ?? this.username,
    password: password ?? this.password,
    bypass: bypass ?? this.bypass,
  );

  /// The proxy named by the usual environment variables (`HTTPS_PROXY`,
  /// `HTTP_PROXY`, `ALL_PROXY`, `NO_PROXY`, upper or lower case) for [url],
  /// or null. This is what "system" means here; the operating system's own
  /// proxy settings are not read.
  static ProxyConfig? fromEnvironment(Uri url, Map<String, String> env) {
    String? get(String name) =>
        env[name.toUpperCase()] ?? env[name.toLowerCase()];
    final noProxy = (get('NO_PROXY') ?? '')
        .split(',')
        .map((e) => e.trim())
        .where((e) => e.isNotEmpty)
        .toList();
    final raw =
        (url.scheme == 'https' ? get('HTTPS_PROXY') : get('HTTP_PROXY')) ??
        get('ALL_PROXY');
    if (raw == null || raw.trim().isEmpty) return null;
    final uri = Uri.tryParse(raw.contains('://') ? raw : 'http://$raw');
    if (uri == null || uri.host.isEmpty) return null;
    final socks = uri.scheme.startsWith('socks');
    final info = uri.userInfo.split(':');
    final config = ProxyConfig(
      kind: socks ? ProxyKind.socks5 : ProxyKind.http,
      host: uri.host,
      port: uri.hasPort ? uri.port : (socks ? 1080 : 8080),
      username: Uri.decodeComponent(info.first),
      password: info.length > 1
          ? Uri.decodeComponent(info.sublist(1).join(':'))
          : '',
      bypass: noProxy,
    );
    return config.bypasses(url.host) ? null : config;
  }
}
