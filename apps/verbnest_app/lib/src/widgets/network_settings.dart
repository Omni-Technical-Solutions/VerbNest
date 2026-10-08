import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:verbnest_http/verbnest_http.dart';

import '../state/file_port.dart';
import '../state/network_state.dart';
import 'cookie_manager.dart';
import 'synced_field.dart';
import '../../l10n/l10n.dart';
import 'ui/toast.dart';

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
            context: context,
            builder: (_) => const CookieManagerDialog(),
          ),
        ),
        SwitchListTile(
          key: const Key('proxy-enabled'),
          title: Text(context.l10n.nsUseProxy),
          value: c.proxyEnabled,
          onChanged: (v) => n.update((x) => x.copyWith(proxyEnabled: v)),
        ),
        if (c.proxyEnabled) ..._proxyFields(context, c, n),
        SwitchListTile(
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
        trailing: IconButton(
          tooltip: context.l10n.nsRemove,
          icon: const Icon(Icons.delete_outline),
          onPressed: () => n.removeCa(i),
        ),
      ),
    for (final cert in c.clientCerts)
      ListTile(
        key: Key('client-cert-${cert.id}'),
        dense: true,
        leading: const Icon(Icons.badge_outlined),
        title: Text(cert.name),
        subtitle: Text(context.l10n.nsClientCertFor(cert.pattern)),
        trailing: IconButton(
          tooltip: context.l10n.nsRemove,
          icon: const Icon(Icons.delete_outline),
          onPressed: () => n.removeClientCert(cert.id),
        ),
      ),
  ];

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
              onPressed: () async {
                final err = await n.addCa(ref.read(filePortProvider));
                if (err != null && context.mounted) {
                  showToast(context, err);
                }
              },
            ),
          ),
          OutlinedButton.icon(
            key: const Key('add-client-cert'),
            icon: const Icon(Icons.add),
            label: Text(context.l10n.nsAddClientCert),
            onPressed: () => showDialog<void>(
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
  const _ClientCertDialog();

  @override
  ConsumerState<_ClientCertDialog> createState() => _ClientCertDialogState();
}

class _ClientCertDialogState extends ConsumerState<_ClientCertDialog> {
  final _host = TextEditingController(text: '*');
  final _pass = TextEditingController();
  PickedFile? _cert;
  PickedFile? _key;

  @override
  void dispose() {
    _host.dispose();
    _pass.dispose();
    super.dispose();
  }

  bool get _isPem =>
      _cert != null &&
      latin1
          .decode(_cert!.bytes.take(80).toList(), allowInvalid: true)
          .contains('-----BEGIN');

  Future<void> _pick(bool key) async {
    final f = await ref.read(filePortProvider).pick();
    if (f != null) setState(() => key ? _key = f : _cert = f);
  }

  @override
  Widget build(BuildContext context) {
    final needsKey = _isPem;
    return AlertDialog(
      title: Text(context.l10n.nsClientCertTitle),
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
            ListTile(
              key: const Key('pick-cert'),
              contentPadding: EdgeInsets.zero,
              title: Text(_cert?.name ?? context.l10n.nsChooseCert),
              trailing: const Icon(Icons.folder_open),
              onTap: () => _pick(false),
            ),
            if (needsKey)
              ListTile(
                key: const Key('pick-key'),
                contentPadding: EdgeInsets.zero,
                title: Text(_key?.name ?? context.l10n.nsChooseKey),
                trailing: const Icon(Icons.folder_open),
                onTap: () => _pick(true),
              ),
            TextField(
              key: const Key('cert-pass'),
              controller: _pass,
              obscureText: true,
              decoration: InputDecoration(labelText: context.l10n.nsPassphrase),
            ),
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
          onPressed: _cert == null || (needsKey && _key == null)
              ? null
              : () {
                  ref
                      .read(networkProvider.notifier)
                      .addClientCert(
                        pattern: _host.text,
                        name: _cert!.name,
                        certificate: _cert!.bytes,
                        privateKey: needsKey ? _key!.bytes : null,
                        passphrase: _pass.text,
                      );
                  Navigator.pop(context);
                },
          child: Text(context.l10n.nsAdd),
        ),
      ],
    );
  }
}
