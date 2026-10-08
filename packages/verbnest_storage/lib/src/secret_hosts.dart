import 'secret_store.dart';

/// Which hosts each secret variable may be sent to.
///
/// The list lives in the same [SecretStore] as the secrets (owner kind
/// [secretHostsKind], owner id = secret name, key = host), so a copy of a
/// workspace file cannot carry or widen it. A tampered file that points a
/// secret at another host is stopped until the user approves that host.
const secretHostsKind = '__hosts';

class SecretHosts {
  SecretHosts(this.store, this.workspaceId, {this.extra = const {}});

  final SecretStore store;
  final String workspaceId;

  /// Approvals that are not stored, like the CLI's `--allow-secret-host`.
  /// Keys are secret names or `*`; values are hosts or `*`.
  final Map<String, Set<String>> extra;

  static String hostOf(Uri url) => url.host.toLowerCase();

  Set<String> allowed(String secretName) => {
    ...store.values(workspaceId, secretHostsKind, secretName).keys,
    ...?extra[secretName],
    ...?extra['*'],
  };

  bool isAllowed(String secretName, String host) {
    final a = allowed(secretName);
    return a.contains('*') || a.contains(host.toLowerCase());
  }

  /// The secrets in [names] that may not be sent to [url]'s host.
  List<String> blocked(Iterable<String> names, Uri url) {
    final host = hostOf(url);
    return [
      for (final n in names)
        if (!isAllowed(n, host)) n,
    ]..sort();
  }

  void allow(Iterable<String> names, String host) {
    for (final n in names) {
      store.put(workspaceId, secretHostsKind, n, host.toLowerCase(), '1');
    }
  }
}
