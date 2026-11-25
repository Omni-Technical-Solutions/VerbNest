import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

import '../../../l10n/l10n.dart';
import '../../state/keystore_relay.dart';
import '../../state/network_state.dart';
import '../keystore_dialog.dart';
import '../network_settings.dart';
import '../pin_settings.dart';

/// Where a request's URL points, as far as certificates are concerned.
class TlsTarget {
  const TlsTarget({
    this.host,
    this.port,
    this.secure = true,
    this.variable = false,
  });

  /// The host, or null when the URL is empty or the host is a variable.
  final String? host;
  final int? port;

  /// False for `http://` and `ws://`: certificates only apply to TLS.
  final bool secure;

  /// The host is (or contains) a `{{variable}}`.
  final bool variable;

  /// The host pattern to start a new entry with: `host`, `host:port`, or `*`.
  String get pattern => host == null
      ? '*'
      : (port == null || port == 443 ? host! : '$host:$port');

  /// What the request's [url] says; a missing scheme counts as https.
  static TlsTarget parse(String url) {
    var t = url.trim();
    var secure = true;
    final i = t.indexOf('://');
    if (i >= 0) {
      final scheme = t.substring(0, i).toLowerCase();
      secure = scheme == 'https' || scheme == 'wss';
      t = t.substring(i + 3);
    }
    final end = t.indexOf(RegExp('[/?#]'));
    final authority = end < 0 ? t : t.substring(0, end);
    if (authority.contains('{{')) {
      return TlsTarget(secure: secure, variable: true);
    }
    final u = Uri.tryParse('https://$authority');
    if (u == null || u.host.isEmpty) return TlsTarget(secure: secure);
    return TlsTarget(
      host: u.host,
      port: u.hasPort ? u.port : (secure ? 443 : 80),
      secure: secure,
    );
  }
}

/// The Headers tab's certificates section: says which client certificate and
/// CAs apply to this request's host and adds, validated, whatever is missing.
/// Everything is stored in the network settings (never in the request), so
/// the Settings page shows the same entries.
class TlsCertificatesSection extends ConsumerWidget {
  const TlsCertificatesSection({super.key, required this.url});

  final String url;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final target = TlsTarget.parse(url);
    final config = ref.watch(networkProvider);
    final keystore = ref.watch(keystoreSupportedProvider).value ?? false;
    return ExpansionTile(
      expansionAnimationStyle: AnimationStyle.noAnimation,
      key: const Key('tls-certificates'),
      dense: true,
      title: Text(context.l10n.tlsSection),
      subtitle: Text(context.l10n.tlsSectionHint),
      childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
      expandedCrossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(key: const Key('tls-status'), _status(context, target, config)),
        const SizedBox(height: 4),
        Text(
          key: const Key('tls-ca-count'),
          context.l10n.tlsCaCount(config.cas.length),
        ),
        const SizedBox(height: 8),
        if (target.secure || target.variable)
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: _buttons(context, ref, target, keystore),
          ),
      ],
    );
  }

  String _status(BuildContext context, TlsTarget t, NetworkConfig config) {
    final l = context.l10n;
    if (!t.secure) return l.tlsHttpsOnly;
    if (t.variable) return l.tlsVariableHost;
    final host = t.host;
    if (host == null) return l.tlsHttpsOnly;
    final entry = config.tls?.selectFor(host, port: t.port);
    if (entry == null) return l.tlsNoCert(host);
    if (entry.isNone) return l.tlsNoneSent(host);
    return l.tlsCertUsed(host, entry.label, entry.hostPattern);
  }

  List<Widget> _buttons(
    BuildContext context,
    WidgetRef ref,
    TlsTarget t,
    bool keystore,
  ) => [
    OutlinedButton.icon(
      key: const Key('tls-add-cert'),
      icon: const Icon(Icons.badge_outlined),
      label: Text(context.l10n.nsAddClientCert),
      onPressed: () => showClientCertDialog(context, host: t.pattern),
    ),
    OutlinedButton.icon(
      key: const Key('tls-add-ca'),
      icon: const Icon(Icons.verified_user_outlined),
      label: Text(context.l10n.nsAddCa),
      onPressed: () => addTrustedCa(context, ref),
    ),
    if (keystore)
      OutlinedButton.icon(
        key: const Key('tls-add-keystore'),
        icon: const Icon(Icons.vpn_key_outlined),
        label: Text(context.l10n.ksAdd),
        onPressed: () => showKeystoreCert(context, host: t.pattern),
      ),
    OutlinedButton.icon(
      key: const Key('tls-no-cert'),
      icon: const Icon(Icons.block),
      label: Text(context.l10n.tlsSendNone),
      onPressed: () =>
          ref.read(networkProvider.notifier).addNoClientCert(t.pattern),
    ),
    if (t.host != null)
      OutlinedButton.icon(
        key: const Key('tls-test'),
        icon: const Icon(Icons.network_check),
        label: Text(context.l10n.tlsTest),
        onPressed: () => showDialog<void>(
          animationStyle: AnimationStyle.noAnimation,
          context: context,
          builder: (_) => TestConnectionDialog(initialUrl: t.pattern),
        ),
      ),
  ];
}
