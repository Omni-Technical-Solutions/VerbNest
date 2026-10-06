import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:verbnest_core/verbnest_core.dart';
import 'package:verbnest_http/verbnest_http.dart';

import 'file_port.dart';
import 'session.dart';

const _kind = 'network';
const _kvKey = 'network';

/// A trusted CA the user added.
class CaEntry {
  const CaEntry(this.name, this.bytes);

  final String name;
  final Uint8List bytes;
}

/// A client certificate for hosts matching [pattern]. The private key and
/// passphrase live in the secret store, not in [NetworkConfig]'s JSON.
class ClientCertEntry {
  const ClientCertEntry({
    required this.id,
    required this.pattern,
    required this.name,
    required this.certificate,
    this.privateKey,
    this.passphrase = '',
  });

  final String id;
  final String pattern;
  final String name;
  final Uint8List certificate;
  final Uint8List? privateKey;
  final String passphrase;
}

/// Proxy and certificate settings. Device-local on purpose: they describe
/// this machine's network, so they do not travel with the workspace file.
class NetworkConfig {
  const NetworkConfig({
    this.proxyEnabled = false,
    this.proxyKind = ProxyKind.http,
    this.proxyHost = '',
    this.proxyPort = 8080,
    this.proxyUser = '',
    this.proxyPassword = '',
    this.bypass = '',
    this.useSystemProxy = false,
    this.cas = const [],
    this.clientCerts = const [],
  });

  final bool proxyEnabled;
  final ProxyKind proxyKind;
  final String proxyHost;
  final int proxyPort;
  final String proxyUser;
  final String proxyPassword;

  /// Comma or space separated host patterns.
  final String bypass;
  final bool useSystemProxy;
  final List<CaEntry> cas;
  final List<ClientCertEntry> clientCerts;

  NetworkConfig copyWith({
    bool? proxyEnabled,
    ProxyKind? proxyKind,
    String? proxyHost,
    int? proxyPort,
    String? proxyUser,
    String? proxyPassword,
    String? bypass,
    bool? useSystemProxy,
    List<CaEntry>? cas,
    List<ClientCertEntry>? clientCerts,
  }) => NetworkConfig(
    proxyEnabled: proxyEnabled ?? this.proxyEnabled,
    proxyKind: proxyKind ?? this.proxyKind,
    proxyHost: proxyHost ?? this.proxyHost,
    proxyPort: proxyPort ?? this.proxyPort,
    proxyUser: proxyUser ?? this.proxyUser,
    proxyPassword: proxyPassword ?? this.proxyPassword,
    bypass: bypass ?? this.bypass,
    useSystemProxy: useSystemProxy ?? this.useSystemProxy,
    cas: cas ?? this.cas,
    clientCerts: clientCerts ?? this.clientCerts,
  );

  ProxyConfig? get proxy => proxyEnabled && proxyHost.trim().isNotEmpty
      ? ProxyConfig(
          kind: proxyKind,
          host: proxyHost.trim(),
          port: proxyPort,
          username: proxyUser,
          password: proxyPassword,
          bypass: bypass
              .split(RegExp(r'[,\s]+'))
              .where((e) => e.isNotEmpty)
              .toList(),
        )
      : null;

  TlsConfig? get tls => cas.isEmpty && clientCerts.isEmpty
      ? null
      : TlsConfig(
          caCertificates: [for (final c in cas) c.bytes],
          clientCertificates: [
            for (final c in clientCerts)
              ClientCertificate(
                hostPattern: c.pattern,
                certificate: c.certificate,
                privateKey: c.privateKey,
                passphrase: c.passphrase,
              ),
          ],
        );
}

class NetworkNotifier extends Notifier<NetworkConfig> {
  @override
  NetworkConfig build() {
    final s = ref.read(sessionProvider);
    final ws = s.repo.workspaceId;
    final raw = s.local.kv(ws, _kvKey);
    if (raw == null) return const NetworkConfig();
    try {
      final j = jsonDecode(raw) as Map<String, Object?>;
      final secrets = s.secrets.values(ws, _kind, 'config');
      Uint8List bytes(Object? v) => base64Decode(v as String);
      return NetworkConfig(
        proxyEnabled: j['proxyEnabled'] as bool? ?? false,
        proxyKind: j['proxyKind'] == 'socks5'
            ? ProxyKind.socks5
            : ProxyKind.http,
        proxyHost: j['proxyHost'] as String? ?? '',
        proxyPort: j['proxyPort'] as int? ?? 8080,
        proxyUser: j['proxyUser'] as String? ?? '',
        proxyPassword: secrets['proxyPassword'] ?? '',
        bypass: j['bypass'] as String? ?? '',
        useSystemProxy: j['useSystemProxy'] as bool? ?? false,
        cas: [
          for (final c in (j['cas'] as List? ?? const []).cast<Map>())
            CaEntry(c['name'] as String, bytes(c['pem'])),
        ],
        clientCerts: [
          for (final c in (j['certs'] as List? ?? const []).cast<Map>())
            ClientCertEntry(
              id: c['id'] as String,
              pattern: c['pattern'] as String,
              name: c['name'] as String,
              certificate: bytes(c['cert']),
              privateKey: secrets['key.${c['id']}'] == null
                  ? null
                  : bytes(secrets['key.${c['id']}']),
              passphrase: secrets['pass.${c['id']}'] ?? '',
            ),
        ],
      );
    } on Object {
      return const NetworkConfig();
    }
  }

  void set(NetworkConfig next) {
    final s = ref.read(sessionProvider);
    final ws = s.repo.workspaceId;
    s.local.setKv(
      ws,
      _kvKey,
      jsonEncode({
        'proxyEnabled': next.proxyEnabled,
        'proxyKind': next.proxyKind.name,
        'proxyHost': next.proxyHost,
        'proxyPort': next.proxyPort,
        'proxyUser': next.proxyUser,
        'bypass': next.bypass,
        'useSystemProxy': next.useSystemProxy,
        'cas': [
          for (final c in next.cas)
            {'name': c.name, 'pem': base64Encode(c.bytes)},
        ],
        'certs': [
          for (final c in next.clientCerts)
            {
              'id': c.id,
              'pattern': c.pattern,
              'name': c.name,
              'cert': base64Encode(c.certificate),
            },
        ],
      }),
    );
    final wanted = <String, String>{
      if (next.proxyPassword.isNotEmpty) 'proxyPassword': next.proxyPassword,
      for (final c in next.clientCerts) ...{
        if (c.privateKey != null) 'key.${c.id}': base64Encode(c.privateKey!),
        if (c.passphrase.isNotEmpty) 'pass.${c.id}': c.passphrase,
      },
    };
    final have = s.secrets.values(ws, _kind, 'config');
    for (final k in have.keys) {
      if (!wanted.containsKey(k)) s.secrets.remove(ws, _kind, 'config', k);
    }
    wanted.forEach((k, v) {
      if (have[k] != v) s.secrets.put(ws, _kind, 'config', k, v);
    });
    state = next;
  }

  void update(NetworkConfig Function(NetworkConfig c) f) => set(f(state));

  /// Reads a CA file the user picks. Returns the error to show, or null.
  Future<String?> addCa(FilePort files) async {
    final f = await files.pick();
    if (f == null) return null;
    if (!_looksLikeCertificate(f.bytes)) {
      return '${f.name} is not a PEM or DER certificate';
    }
    update((c) => c.copyWith(cas: [...c.cas, CaEntry(f.name, f.bytes)]));
    return null;
  }

  void removeCa(int index) =>
      update((c) => c.copyWith(cas: [...c.cas]..removeAt(index)));

  void removeClientCert(String id) => update(
    (c) => c.copyWith(
      clientCerts: c.clientCerts.where((e) => e.id != id).toList(),
    ),
  );

  /// Adds a client certificate. For PKCS#12 pass only [certificate].
  void addClientCert({
    required String pattern,
    required String name,
    required Uint8List certificate,
    Uint8List? privateKey,
    String passphrase = '',
  }) => update(
    (c) => c.copyWith(
      clientCerts: [
        ...c.clientCerts,
        ClientCertEntry(
          id: DateTime.now().microsecondsSinceEpoch.toRadixString(36),
          pattern: pattern.trim().isEmpty ? '*' : pattern.trim(),
          name: name,
          certificate: certificate,
          privateKey: privateKey,
          passphrase: passphrase,
        ),
      ],
    ),
  );
}

bool _looksLikeCertificate(Uint8List b) {
  final head = latin1.decode(b.take(64).toList(), allowInvalid: true);
  return head.contains('-----BEGIN') || (b.isNotEmpty && b.first == 0x30);
}

final networkProvider = NotifierProvider<NetworkNotifier, NetworkConfig>(
  NetworkNotifier.new,
);

/// The cookie jar shared by every request in the open workspace (FR-HTTP-011).
/// The state is the cookie list so views rebuild when it changes.
class CookiesNotifier extends Notifier<List<StoredCookie>> {
  late final CookieJar jar;

  @override
  List<StoredCookie> build() {
    final s = ref.read(sessionProvider);
    final ws = s.repo.workspaceId;
    final raw = s.local.kv(ws, 'cookies');
    var loaded = CookieJar();
    if (raw != null) {
      try {
        loaded = CookieJar.fromJson(jsonDecode(raw));
      } on Object {
        // A damaged jar is dropped rather than blocking sends.
      }
    }
    jar = loaded;
    final now = DateTime.now();
    for (final c in jar.cookies.where((c) => c.isExpired(now))) {
      jar.remove(c);
    }
    jar.onChanged = () {
      s.local.setKv(ws, 'cookies', jsonEncode(jar.toJson()));
      state = jar.cookies;
    };
    return jar.cookies;
  }

  void remove(StoredCookie c) => jar.remove(c);

  void removeDomain(String domain) => jar.removeDomain(domain);

  void clear() => jar.clear();
}

final cookiesProvider = NotifierProvider<CookiesNotifier, List<StoredCookie>>(
  CookiesNotifier.new,
);
