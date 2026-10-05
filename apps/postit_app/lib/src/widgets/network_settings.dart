import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:postit_http/postit_http.dart';

import '../state/file_port.dart';
import '../state/network_state.dart';
import 'cookie_manager.dart';
import 'synced_field.dart';

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
          child: Text('Network (this device)', style: theme),
        ),
        ListTile(
          key: const Key('open-cookies'),
          leading: const Icon(Icons.cookie_outlined),
          title: Text('Cookies (${ref.watch(cookiesProvider).length})'),
          subtitle: const Text('Saved from responses and sent automatically'),
          onTap: () => showDialog<void>(
            context: context,
            builder: (_) => const CookieManagerDialog(),
          ),
        ),
        SwitchListTile(
          key: const Key('proxy-enabled'),
          title: const Text('Use a proxy'),
          value: c.proxyEnabled,
          onChanged: (v) => n.update((x) => x.copyWith(proxyEnabled: v)),
        ),
        if (c.proxyEnabled) ...[
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
            child: SegmentedButton<ProxyKind>(
              key: const Key('proxy-kind'),
              segments: const [
                ButtonSegment(value: ProxyKind.http, label: Text('HTTP')),
                ButtonSegment(value: ProxyKind.socks5, label: Text('SOCKS5')),
              ],
              selected: {c.proxyKind},
              onSelectionChanged: (s) =>
                  n.update((x) => x.copyWith(proxyKind: s.first)),
            ),
          ),
          _field(
            'proxy-host',
            'Proxy host',
            c.proxyHost,
            (v) => n.update((x) => x.copyWith(proxyHost: v.trim())),
          ),
          _field('proxy-port', 'Proxy port', '${c.proxyPort}', (v) {
            final p = int.tryParse(v.trim());
            if (p != null && p > 0 && p < 65536) {
              n.update((x) => x.copyWith(proxyPort: p));
            }
          }),
          _field(
            'proxy-user',
            'Proxy user name (optional)',
            c.proxyUser,
            (v) => n.update((x) => x.copyWith(proxyUser: v)),
          ),
          _field(
            'proxy-password',
            'Proxy password (optional)',
            c.proxyPassword,
            (v) => n.update((x) => x.copyWith(proxyPassword: v)),
            obscure: true,
          ),
          _field(
            'proxy-bypass',
            'No proxy for (comma separated hosts)',
            c.bypass,
            (v) => n.update((x) => x.copyWith(bypass: v)),
          ),
        ],
        SwitchListTile(
          key: const Key('system-proxy'),
          title: const Text('Use HTTP_PROXY / HTTPS_PROXY / NO_PROXY'),
          subtitle: const Text(
            'Read from the environment when no proxy is set above. '
            'The operating system proxy settings are not read.',
          ),
          value: c.useSystemProxy,
          onChanged: (v) => n.update((x) => x.copyWith(useSystemProxy: v)),
        ),
        const Divider(),
        Padding(
          padding: const EdgeInsetsDirectional.fromSTEB(16, 8, 16, 0),
          child: Text('Certificates (this device)', style: theme),
        ),
        for (var i = 0; i < c.cas.length; i++)
          ListTile(
            key: Key('ca-$i'),
            dense: true,
            leading: const Icon(Icons.verified_user_outlined),
            title: Text(c.cas[i].name),
            subtitle: const Text('Trusted certificate authority'),
            trailing: IconButton(
              tooltip: 'Remove',
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
            subtitle: Text('Client certificate for ${cert.pattern}'),
            trailing: IconButton(
              tooltip: 'Remove',
              icon: const Icon(Icons.delete_outline),
              onPressed: () => n.removeClientCert(cert.id),
            ),
          ),
        Wrap(
          spacing: 8,
          children: [
            Padding(
              padding: const EdgeInsetsDirectional.only(start: 16),
              child: OutlinedButton.icon(
                key: const Key('add-ca'),
                icon: const Icon(Icons.add),
                label: const Text('Add trusted CA'),
                onPressed: () async {
                  final err = await n.addCa(ref.read(filePortProvider));
                  if (err != null && context.mounted) {
                    ScaffoldMessenger.of(context)
                        .showSnackBar(SnackBar(content: Text(err)));
                  }
                },
              ),
            ),
            OutlinedButton.icon(
              key: const Key('add-client-cert'),
              icon: const Icon(Icons.add),
              label: const Text('Add client certificate'),
              onPressed: () => showDialog<void>(
                context: context,
                builder: (_) => const _ClientCertDialog(),
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
      ],
    );
  }

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
      title: const Text('Client certificate'),
      content: SizedBox(
        width: 420,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              key: const Key('cert-host'),
              controller: _host,
              decoration: const InputDecoration(
                labelText: 'Hosts (api.example.com, *.example.com or *)',
              ),
            ),
            ListTile(
              key: const Key('pick-cert'),
              contentPadding: EdgeInsets.zero,
              title: Text(_cert?.name ?? 'Choose certificate (.pem, .p12)'),
              trailing: const Icon(Icons.folder_open),
              onTap: () => _pick(false),
            ),
            if (needsKey)
              ListTile(
                key: const Key('pick-key'),
                contentPadding: EdgeInsets.zero,
                title: Text(_key?.name ?? 'Choose private key (.pem)'),
                trailing: const Icon(Icons.folder_open),
                onTap: () => _pick(true),
              ),
            TextField(
              key: const Key('cert-pass'),
              controller: _pass,
              obscureText: true,
              decoration: const InputDecoration(
                labelText: 'Passphrase (optional)',
              ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
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
          child: const Text('Add'),
        ),
      ],
    );
  }
}
