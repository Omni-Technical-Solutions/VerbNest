import 'ui/still_controls.dart';

import 'package:material_ui/material_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:verbnest_http/verbnest_http.dart';

import '../state/file_port.dart';
import '../state/network_state.dart';
import '../state/keystore_relay.dart';
import 'cookie_manager.dart';
import 'keystore_dialog.dart';
import 'network_export_dialog.dart';
import 'pin_settings.dart';
import 'synced_field.dart';
import '../../l10n/l10n.dart';
import 'ui/toast.dart';
import 'ui/still_tooltip.dart';

/// Proxy, certificates and cookies (FR-HTTP-011..013), shown in Settings.
class NetworkSettingsSection extends ConsumerWidget {
  const NetworkSettingsSection({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = ref.watch(networkProvider);
    final n = ref.read(networkProvider.notifier);
    final theme = Theme.of(context).textTheme.titleSmall;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsetsDirectional.fromSTEB(16, 8, 16, 0),
          child: Text(context.l10n.nsTitle, style: theme),
        ),
        ListTile(
          key: const Key('open-cookies'),
          leading: const Icon(Icons.cookie_outlined),
          title: Text(
            context.l10n.nsCookies(ref.watch(cookiesProvider).length),
          ),
          subtitle: Text(context.l10n.nsCookiesHint),
          onTap: () => showDialog<void>(
            animationStyle: AnimationStyle.noAnimation,
            context: context,
            builder: (_) => const CookieManagerDialog(),
          ),
        ),
        StillSwitchListTile(
          key: const Key('proxy-enabled'),
          title: Text(context.l10n.nsUseProxy),
          value: c.proxyEnabled,
          onChanged: (v) => n.update((x) => x.copyWith(proxyEnabled: v)),
        ),
        if (c.proxyEnabled) ..._proxyFields(context, c, n),
        StillSwitchListTile(
          key: const Key('system-proxy'),
          title: Text(context.l10n.nsSystemProxy),
          subtitle: Text(context.l10n.nsSystemProxyHint),
          value: c.useSystemProxy,
          onChanged: (v) => n.update((x) => x.copyWith(useSystemProxy: v)),
        ),
        const Divider(),
        Padding(
          padding: const EdgeInsetsDirectional.fromSTEB(16, 8, 16, 0),
          child: Text(context.l10n.nsCertsTitle, style: theme),
        ),
        ..._certTiles(context, c, n),
        _addButtons(context, ref, n),
        const Divider(),
        const PinSettingsSection(),
        const SizedBox(height: 8),
      ],
    );
  }

  List<Widget> _proxyFields(
    BuildContext context,
    NetworkConfig c,
    NetworkNotifier n,
  ) => [
    Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      child: SegmentedButton<ProxyKind>(
        key: const Key('proxy-kind'),
        segments: [
          ButtonSegment(
            value: ProxyKind.http,
            label: Text(context.l10n.nsProxyHttp),
          ),
          ButtonSegment(
            value: ProxyKind.socks5,
            label: Text(context.l10n.nsProxySocks),
          ),
        ],
        selected: {c.proxyKind},
        onSelectionChanged: (s) =>
            n.update((x) => x.copyWith(proxyKind: s.first)),
      ),
    ),
    _field(
      'proxy-host',
      context.l10n.nsProxyHost,
      c.proxyHost,
      (v) => n.update((x) => x.copyWith(proxyHost: v.trim())),
    ),
    _field('proxy-port', context.l10n.nsProxyPort, '${c.proxyPort}', (v) {
      final p = int.tryParse(v.trim());
      if (p != null && p > 0 && p < 65536) {
        n.update((x) => x.copyWith(proxyPort: p));
      }
    }),
    _field(
      'proxy-user',
      context.l10n.nsProxyUser,
      c.proxyUser,
      (v) => n.update((x) => x.copyWith(proxyUser: v)),
    ),
    _field(
      'proxy-password',
      context.l10n.nsProxyPassword,
      c.proxyPassword,
      (v) => n.update((x) => x.copyWith(proxyPassword: v)),
      obscure: true,
    ),
    _field(
      'proxy-bypass',
      context.l10n.nsProxyBypass,
      c.bypass,
      (v) => n.update((x) => x.copyWith(bypass: v)),
    ),
  ];

  List<Widget> _certTiles(
    BuildContext context,
    NetworkConfig c,
    NetworkNotifier n,
  ) => [
    for (var i = 0; i < c.cas.length; i++)
      ListTile(
        key: Key('ca-$i'),
        dense: true,
        leading: const Icon(Icons.verified_user_outlined),
        title: Text(c.cas[i].name),
        subtitle: Text(context.l10n.nsCaHint),
        trailing: StillIconButton(
          tooltip: context.l10n.nsRemove,
          icon: const Icon(Icons.delete_outline),
          onPressed: () => n.removeCa(i),
        ),
      ),
    for (final cert in c.clientCerts)
      ListTile(
        key: Key('client-cert-${cert.id}'),
        dense: true,
        leading: Icon(
          cert.none
              ? Icons.block
              : cert.isKeystore
              ? Icons.vpn_key_outlined
              : Icons.badge_outlined,
          color: cert.enabled ? null : Theme.of(context).disabledColor,
        ),
        title: Text(cert.name),
        subtitle: _certSubtitle(context, cert),
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Switch(
              key: Key('cert-enabled-${cert.id}'),
              value: cert.enabled,
              onChanged: (v) => n.setClientCertEnabled(cert.id, v),
            ),
            StillIconButton(
              key: Key('edit-cert-${cert.id}'),
              tooltip: context.l10n.nsCertEdit,
              icon: const Icon(Icons.edit_outlined),
              onPressed: () => cert.isKeystore
                  ? showKeystoreCert(context, existing: cert)
                  : showDialog<void>(
                      animationStyle: AnimationStyle.noAnimation,
                      context: context,
                      builder: (_) => _ClientCertDialog(existing: cert),
                    ),
            ),
            StillIconButton(
              tooltip: context.l10n.nsRemove,
              icon: const Icon(Icons.delete_outline),
              onPressed: () => n.removeClientCert(cert.id),
            ),
          ],
        ),
      ),
  ];

  /// The host pattern and, for a PEM certificate, when it runs out; the part
  /// about expiry is in the error colour once it is past or under 30 days.
  Widget _certSubtitle(BuildContext context, ClientCertEntry cert) {
    final l = context.l10n;
    if (cert.isKeystore) return Text(l.ksKeystoreEntry(cert.pattern));
    final base = l.nsClientCertFor(cert.pattern);
    final info = cert.enabled ? clientCertInfo(cert) : null;
    if (info == null) return Text(base);
    final now = DateTime.now();
    final date = info.notAfter.toIso8601String().substring(0, 10);
    final expired = info.isExpired(now);
    final soon = !expired && info.daysLeft(now) < 30;
    return Text.rich(
      TextSpan(
        text: '$base · ',
        children: [
          TextSpan(
            text: expired ? l.nsCertExpiredOn(date) : l.nsCertExpires(date),
            style: expired || soon
                ? TextStyle(color: Theme.of(context).colorScheme.error)
                : null,
          ),
        ],
      ),
    );
  }

  Widget _addButtons(BuildContext context, WidgetRef ref, NetworkNotifier n) =>
      Wrap(
        spacing: 8,
        children: [
          Padding(
            padding: const EdgeInsetsDirectional.only(start: 16),
            child: OutlinedButton.icon(
              key: const Key('add-ca'),
              icon: const Icon(Icons.add),
              label: Text(context.l10n.nsAddCa),
              onPressed: () => addTrustedCa(context, ref),
            ),
          ),
          OutlinedButton.icon(
            key: const Key('export-network'),
            icon: const Icon(Icons.terminal),
            label: Text(context.l10n.nsExport),
            onPressed: () => showNetworkExport(context),
          ),
          if (ref.watch(keystoreSupportedProvider).value ?? false)
            OutlinedButton.icon(
              key: const Key('add-keystore-cert'),
              icon: const Icon(Icons.vpn_key_outlined),
              label: Text(context.l10n.ksAdd),
              onPressed: () => showKeystoreCert(context),
            ),
          OutlinedButton.icon(
            key: const Key('add-client-cert'),
            icon: const Icon(Icons.add),
            label: Text(context.l10n.nsAddClientCert),
            onPressed: () => showDialog<void>(
              animationStyle: AnimationStyle.noAnimation,
              context: context,
              builder: (_) => const _ClientCertDialog(),
            ),
          ),
        ],
      );

  Widget _field(
    String key,
    String label,
    String value,
    ValueChanged<String> onChanged, {
    bool obscure = false,
  }) => Padding(
    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
    child: SyncedTextField(
      key: Key(key),
      label: label,
      value: value,
      obscure: obscure,
      onChanged: onChanged,
    ),
  );
}

/// Asks for the host pattern, the files and the passphrase.
class _ClientCertDialog extends ConsumerStatefulWidget {
  const _ClientCertDialog({this.existing, this.initialHost});

  /// The host pattern to start with when adding (the request's host when the
  /// dialog is opened from the Headers tab).
  final String? initialHost;

  /// The entry being edited; null when adding one.
  final ClientCertEntry? existing;

  @override
  ConsumerState<_ClientCertDialog> createState() => _ClientCertDialogState();
}

class _ClientCertDialogState extends ConsumerState<_ClientCertDialog> {
  late final _host = TextEditingController(
    text: widget.existing?.pattern ?? widget.initialHost ?? '*',
  );
  late final _pass = TextEditingController(
    text: widget.existing?.passphrase ?? '',
  );

  /// What the entry is called in the list and in the TLS panel; the
  /// certificate's file name until the person types another.
  late final _name = TextEditingController(text: widget.existing?.name ?? '');
  PickedFile? _cert;
  PickedFile? _key;

  /// The private key was found inside the certificate file (a combined PEM,
  /// what `openssl pkcs12 -nodes` writes), so no separate key is asked for.
  bool _keyInCert = false;

  /// "Send no client certificate" instead of a certificate.
  bool _none = false;

  @override
  void initState() {
    super.initState();
    final e = widget.existing;
    if (e == null) return;
    _none = e.none;
    if (!e.none) {
      _cert = PickedFile(e.name, e.certificate);
      final k = e.privateKey;
      if (k != null) _key = PickedFile(e.name, k);
      _recheck();
    }
  }

  /// What loading the chosen files and passphrase gave; null until there is
  /// something to check.
  CertCheck? _check;

  @override
  void dispose() {
    _host.dispose();
    _pass.dispose();
    _name.dispose();
    super.dispose();
  }

  bool get _isPem => _cert != null && looksLikePem(_cert!.bytes);

  Future<void> _pick(bool key) async {
    final f = await ref.read(filePortProvider).pick();
    if (f == null) return;
    setState(() {
      if (key) {
        _key = f;
        _keyInCert = false;
      } else {
        // The name follows the file until it has been changed by hand.
        if (_name.text.isEmpty || _name.text == _cert?.name) {
          _name.text = f.name;
        }
        _cert = f;
        // A combined PEM carries its own key; a new certificate drops a key
        // that was taken from the previous one.
        if (_keyInCert || !_isPem) _key = null;
        _keyInCert = _isPem && hasPrivateKeyBlock(f.bytes);
        if (_keyInCert) _key = f;
      }
      _recheck();
    });
  }

  /// Loads the files the way the engine will, so a wrong passphrase or a key
  /// that does not match shows here and not at the first request.
  void _recheck() {
    final cert = _cert;
    if (cert == null) {
      _check = null;
      return;
    }
    // A PEM certificate with no key yet is checked too, so the reason the
    // Add button is off ("choose its private key as well") is on screen.
    _check = checkClientCertificate(
      certificate: cert.bytes,
      privateKey: _isPem ? _key?.bytes : null,
      passphrase: _pass.text,
    );
  }

  void _save(bool needsKey) {
    final n = ref.read(networkProvider.notifier);
    final pattern = _host.text.trim().isEmpty ? '*' : _host.text.trim();
    final old = widget.existing;
    final label = _name.text.trim().isEmpty
        ? (_cert?.name ?? '')
        : _name.text.trim();
    if (_none) {
      if (old == null) {
        n.addNoClientCert(pattern);
      } else {
        n.replaceClientCert(old.copyWith(pattern: pattern));
      }
    } else if (old == null) {
      n.addClientCert(
        pattern: pattern,
        name: label,
        certificate: _cert!.bytes,
        privateKey: needsKey ? _key!.bytes : null,
        passphrase: _pass.text,
      );
    } else {
      n.replaceClientCert(
        old.copyWith(
          pattern: pattern,
          name: label,
          certificate: _cert!.bytes,
          privateKey: needsKey ? _key!.bytes : null,
          clearKey: !needsKey,
          passphrase: _pass.text,
        ),
      );
    }
  }

  /// The outcome of the check: the reason it fails, or what the certificate
  /// says about itself with any warnings.
  Widget _checkResult(BuildContext context) {
    final c = _check;
    if (c == null) return const SizedBox.shrink();
    final l = context.l10n;
    final scheme = Theme.of(context).colorScheme;
    if (!c.ok) {
      return Padding(
        padding: const EdgeInsets.only(top: 8),
        child: Text(
          c.message ?? '',
          key: const Key('cert-problem'),
          style: TextStyle(color: scheme.error),
        ),
      );
    }
    final info = c.info;
    final now = DateTime.now();
    String d(DateTime x) => x.toUtc().toIso8601String().substring(0, 10);
    final lines = <String>[
      if (info == null) l.nsCertBundleOk,
      if (info != null) ...[
        l.rvTlsSubject(info.subject),
        l.rvTlsIssuer(info.issuer),
        l.rvTlsValid(d(info.notBefore), d(info.notAfter)),
        l.nsCertKeyAlgo(info.keyAlgorithm),
        if (info.names.isNotEmpty) l.nsCertNames(info.names.join(', ')),
        l.rvTlsFingerprint(info.sha256),
      ],
    ];
    final warnings = [
      for (final w in c.warnings)
        switch (w) {
          CertWarning.expired => l.nsCertWarnExpired,
          CertWarning.notYetValid => l.nsCertWarnNotYet,
          CertWarning.expiresSoon => l.nsCertWarnSoon('${info!.daysLeft(now)}'),
          CertWarning.selfSigned => l.nsCertWarnSelfSigned,
        },
    ];
    return Padding(
      padding: const EdgeInsets.only(top: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SelectableText(
            lines.join('\n'),
            key: const Key('cert-details'),
            style: Theme.of(context).textTheme.bodySmall,
          ),
          for (final (i, w) in warnings.indexed)
            Text(
              w,
              key: Key('cert-warning-$i'),
              style: TextStyle(color: scheme.error),
            ),
        ],
      ),
    );
  }

  /// The key hint, the call-out that a PEM needs its `.key` file, and the row
  /// that chooses it.
  List<Widget> _keyRows(BuildContext context, bool needsKey) => [
    if (_cert == null && !_none)
      _KeyNote(key: const Key('key-hint'), text: context.l10n.nsKeyHintNoCert),
    if (needsKey && !_none && !_keyInCert)
      _KeyNote(
        key: const Key('key-required-note'),
        text: context.l10n.nsKeyRequiredNote,
        strong: true,
      ),
    if (needsKey && !_none)
      ListTile(
        key: const Key('pick-key'),
        contentPadding: EdgeInsets.zero,
        title: Text(
          _keyInCert
              ? context.l10n.nsKeyInCert
              : (_key?.name ?? context.l10n.nsChooseKey),
        ),
        trailing: const Icon(Icons.folder_open),
        onTap: () => _pick(true),
      ),
  ];

  @override
  Widget build(BuildContext context) {
    // The key row is there whenever the file is a PEM, and also whenever the
    // check says the key is missing, so that message never shows without the
    // control it asks for.
    final needsKey = _isPem || _check?.problem == CertProblem.keyMissing;
    return AlertDialog(
      // The details and warnings can be long: the dialog scrolls.
      scrollable: true,
      title: Text(
        widget.existing == null
            ? context.l10n.nsClientCertTitle
            : context.l10n.nsCertEditTitle,
      ),
      content: SizedBox(
        width: 420,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              key: const Key('cert-host'),
              controller: _host,
              decoration: InputDecoration(labelText: context.l10n.nsCertHosts),
            ),
            if (widget.existing == null || widget.existing!.none)
              CheckboxListTile(
                key: const Key('cert-none'),
                contentPadding: EdgeInsets.zero,
                value: _none,
                title: Text(context.l10n.nsCertNone),
                onChanged: (v) => setState(() => _none = v ?? false),
              ),
            if (!_none)
              ListTile(
                key: const Key('pick-cert'),
                contentPadding: EdgeInsets.zero,
                title: Text(_cert?.name ?? context.l10n.nsChooseCert),
                trailing: const Icon(Icons.folder_open),
                onTap: () => _pick(false),
              ),
            ..._keyRows(context, needsKey),
            if (!_none) ...[
              TextField(
                key: const Key('cert-name'),
                controller: _name,
                decoration: InputDecoration(labelText: context.l10n.nsCertName),
              ),
              TextField(
                key: const Key('cert-pass'),
                controller: _pass,
                obscureText: true,
                decoration: InputDecoration(
                  labelText: context.l10n.nsPassphrase,
                ),
                onChanged: (_) => setState(_recheck),
              ),
              _checkResult(context),
            ],
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: Text(context.l10n.nsCancel),
        ),
        FilledButton(
          key: const Key('save-cert'),
          onPressed: !_none && _check?.ok != true
              ? null
              : () {
                  _save(needsKey);
                  Navigator.pop(context);
                },
          child: Text(context.l10n.nsAdd),
        ),
      ],
    );
  }
}

/// A line of explanation in the certificate dialog; [strong] boxes it so the
/// private key requirement cannot be missed.
class _KeyNote extends StatelessWidget {
  const _KeyNote({super.key, required this.text, this.strong = false});

  final String text;
  final bool strong;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final style = Theme.of(context).textTheme.bodySmall;
    if (!strong) {
      return Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: Text(text, style: style),
      );
    }
    return Container(
      margin: const EdgeInsets.symmetric(vertical: 8),
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: scheme.secondaryContainer,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.vpn_key, size: 18, color: scheme.onSecondaryContainer),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              text,
              style: style?.copyWith(color: scheme.onSecondaryContainer),
            ),
          ),
        ],
      ),
    );
  }
}

/// Opens the client certificate dialog (add), starting with [host] as the
/// host pattern; used by the Settings page and the request's Headers tab.
Future<void> showClientCertDialog(BuildContext context, {String? host}) =>
    showDialog<void>(
      animationStyle: AnimationStyle.noAnimation,
      context: context,
      builder: (_) => _ClientCertDialog(initialHost: host),
    );

/// Adds a trusted CA from a file the person picks, and says what happened.
Future<void> addTrustedCa(BuildContext context, WidgetRef ref) async {
  final r = await ref
      .read(networkProvider.notifier)
      .addCa(ref.read(filePortProvider));
  if (!context.mounted) return;
  final msg =
      r.error ?? (r.added == null ? null : context.l10n.nsCaAdded(r.added!));
  if (msg != null) showToast(context, msg);
}
