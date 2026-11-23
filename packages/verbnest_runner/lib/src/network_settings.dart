import 'dart:convert';
import 'dart:typed_data';

import 'package:verbnest_http/verbnest_http.dart';
import 'package:verbnest_storage/verbnest_storage.dart';

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
    this.enabled = true,
    this.none = false,
  });

  final String id;
  final String pattern;
  final String name;
  final Uint8List certificate;
  final Uint8List? privateKey;
  final String passphrase;

  /// A switched-off entry is kept but never used.
  final bool enabled;

  /// "Send no client certificate to these hosts"; has no certificate.
  final bool none;

  /// A PEM certificate whose private key is not available (it sits in the
  /// secret store, which was not read): it cannot be used yet.
  bool get needsKey =>
      !none &&
      privateKey == null &&
      String.fromCharCodes(certificate.take(200)).contains('-----BEGIN');

  ClientCertEntry copyWith({
    String? pattern,
    String? name,
    Uint8List? certificate,
    Uint8List? privateKey,
    bool clearKey = false,
    String? passphrase,
    bool? enabled,
  }) => ClientCertEntry(
    id: id,
    pattern: pattern ?? this.pattern,
    name: name ?? this.name,
    certificate: certificate ?? this.certificate,
    privateKey: clearKey ? null : (privateKey ?? this.privateKey),
    passphrase: passphrase ?? this.passphrase,
    enabled: enabled ?? this.enabled,
    none: none,
  );
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
              if (c.none)
                ClientCertificate.none(
                  c.pattern,
                  enabled: c.enabled,
                  label: c.name,
                )
              else
                ClientCertificate(
                  hostPattern: c.pattern,
                  certificate: c.certificate,
                  privateKey: c.privateKey,
                  passphrase: c.passphrase,
                  enabled: c.enabled,
                  label: c.name,
                ),
          ],
        );
}

/// The device-local key and secret kind the network settings are stored under.
const networkKind = 'network';
const networkKvKey = 'network';

/// Reads and writes [NetworkConfig] in the device-local store: the settings
/// and certificates as JSON in [LocalStore]'s key/value table, the private
/// keys, passphrases and the proxy password in the [SecretStore]. The app and
/// the command line share this so they read each other's data.
class NetworkConfigStore {
  const NetworkConfigStore(this.local, this.secrets, this.workspaceId);

  final LocalStore local;
  final SecretStore secrets;
  final String workspaceId;

  /// The saved settings, or an empty [NetworkConfig] when there are none or
  /// they cannot be read.
  NetworkConfig read() {
    final raw = local.kv(workspaceId, networkKvKey);
    if (raw == null) return const NetworkConfig();
    try {
      return readJson(
        jsonDecode(raw) as Map<String, Object?>,
        secrets.values(workspaceId, networkKind, 'config'),
      );
    } on Object {
      return const NetworkConfig();
    }
  }

  /// The stored JSON text as a map.
  static Map<String, Object?> decode(String raw) =>
      jsonDecode(raw) as Map<String, Object?>;

  /// [NetworkConfig] from the stored JSON and the secrets map.
  static NetworkConfig readJson(
    Map<String, Object?> j,
    Map<String, String> secrets,
  ) {
    Uint8List bytes(Object? v) => base64Decode(v as String);
    return NetworkConfig(
      proxyEnabled: j['proxyEnabled'] as bool? ?? false,
      proxyKind: j['proxyKind'] == 'socks5' ? ProxyKind.socks5 : ProxyKind.http,
      proxyHost: j['proxyHost'] as String? ?? '',
      proxyPort: j['proxyPort'] as int? ?? 8080,
      proxyUser: j['proxyUser'] as String? ?? '',
      proxyPassword: secrets['proxyPassword'] ?? '',
      bypass: j['bypass'] as String? ?? '',
      useSystemProxy: j['useSystemProxy'] as bool? ?? false,
      cas: [
        for (final c
            in (j['cas'] as List? ?? const []).cast<Map<dynamic, dynamic>>())
          CaEntry(c['name'] as String, bytes(c['pem'])),
      ],
      clientCerts: [
        for (final c
            in (j['certs'] as List? ?? const []).cast<Map<dynamic, dynamic>>())
          ClientCertEntry(
            id: c['id'] as String,
            pattern: c['pattern'] as String,
            name: c['name'] as String,
            certificate: c['none'] == true ? Uint8List(0) : bytes(c['cert']),
            enabled: c['enabled'] as bool? ?? true,
            none: c['none'] as bool? ?? false,
            privateKey: secrets['key.${c['id']}'] == null
                ? null
                : bytes(secrets['key.${c['id']}']),
            passphrase: secrets['pass.${c['id']}'] ?? '',
          ),
      ],
    );
  }

  /// The JSON for [config]: no keys, no passphrases, no proxy password.
  static Map<String, Object?> toJson(NetworkConfig next) => {
    'proxyEnabled': next.proxyEnabled,
    'proxyKind': next.proxyKind.name,
    'proxyHost': next.proxyHost,
    'proxyPort': next.proxyPort,
    'proxyUser': next.proxyUser,
    'bypass': next.bypass,
    'useSystemProxy': next.useSystemProxy,
    'cas': [
      for (final c in next.cas) {'name': c.name, 'pem': base64Encode(c.bytes)},
    ],
    'certs': [
      for (final c in next.clientCerts)
        {
          'id': c.id,
          'pattern': c.pattern,
          'name': c.name,
          if (!c.none) 'cert': base64Encode(c.certificate),
          if (!c.enabled) 'enabled': false,
          if (c.none) 'none': true,
        },
    ],
  };

  /// The secrets [config] needs, by their key in the secret store.
  static Map<String, String> secretsOf(NetworkConfig next) => {
    if (next.proxyPassword.isNotEmpty) 'proxyPassword': next.proxyPassword,
    for (final c in next.clientCerts) ...{
      if (c.privateKey != null) 'key.${c.id}': base64Encode(c.privateKey!),
      if (c.passphrase.isNotEmpty) 'pass.${c.id}': c.passphrase,
    },
  };

  void write(NetworkConfig next) {
    local.setKv(workspaceId, networkKvKey, jsonEncode(toJson(next)));
    final wanted = secretsOf(next);
    final have = secrets.values(workspaceId, networkKind, 'config');
    for (final k in have.keys) {
      if (!wanted.containsKey(k)) {
        secrets.remove(workspaceId, networkKind, 'config', k);
      }
    }
    wanted.forEach((k, v) {
      if (have[k] != v) secrets.put(workspaceId, networkKind, 'config', k, v);
    });
  }
}
