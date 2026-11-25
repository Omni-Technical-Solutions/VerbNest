import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';
import 'package:verbnest_http/verbnest_http.dart';

import '../../l10n/l10n.dart';
import '../state/file_port.dart';
import '../state/keystore_relay.dart';
import '../state/network_state.dart';

/// Adds (or edits) a client certificate that lives in the system keystore
/// (FR-HTTP-013f): pick the identity, say which hosts get it.
Future<void> showKeystoreCert(
  BuildContext context, {
  ClientCertEntry? existing,
  String? host,
}) => showDialog<void>(
  animationStyle: AnimationStyle.noAnimation,
  context: context,
  builder: (_) => KeystoreCertDialog(existing: existing, initialHost: host),
);

class KeystoreCertDialog extends ConsumerStatefulWidget {
  const KeystoreCertDialog({super.key, this.existing, this.initialHost});

  final ClientCertEntry? existing;

  /// The host pattern to start with when adding.
  final String? initialHost;

  @override
  ConsumerState<KeystoreCertDialog> createState() => _KeystoreDialogState();
}

class _KeystoreDialogState extends ConsumerState<KeystoreCertDialog> {
  late final _host = TextEditingController(
    text: widget.existing?.pattern ?? widget.initialHost ?? '*',
  );
  late final _name = TextEditingController(text: widget.existing?.name ?? '');
  final _pass = TextEditingController();
  List<KeystoreIdentity>? _identities;
  String? _error;
  String? _chosen;
  var _busy = false;

  @override
  void initState() {
    super.initState();
    _chosen = widget.existing?.keystoreId;
    _load();
  }

  @override
  void dispose() {
    _host.dispose();
    _name.dispose();
    _pass.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    final relay = ref.read(keystoreRelayProvider);
    try {
      final list = await relay.identities();
      if (mounted) setState(() => _identities = list);
    } on KeystoreError catch (e) {
      if (mounted) {
        setState(() {
          _identities = const [];
          _error = e.message;
        });
      }
    }
  }

  Future<void> _import() async {
    final relay = ref.read(keystoreRelayProvider);
    if (relay is! PlatformKeystoreRelay) return;
    final f = await ref.read(filePortProvider).pick();
    if (f == null) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final id = await relay.import(f.bytes, _pass.text, f.name);
      await _load();
      if (mounted) setState(() => _chosen = id.id);
    } on KeystoreError catch (e) {
      if (mounted) {
        setState(() => _error = context.l10n.ksImportFailed(e.message));
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  /// Android: pick from the credentials installed in the system settings.
  Future<void> _choose() async {
    final relay = ref.read(keystoreRelayProvider);
    if (relay is! PlatformKeystoreRelay) return;
    setState(() => _error = null);
    try {
      final id = await relay.choose();
      final list = [...?_identities];
      if (!list.any((i) => i.id == id.id)) list.add(id);
      if (mounted) {
        setState(() {
          _identities = list;
          _chosen = id.id;
        });
      }
    } on KeystoreError catch (e) {
      if (mounted) setState(() => _error = e.message);
    }
  }

  void _save() {
    final id = _chosen;
    if (id == null) return;
    final list = _identities ?? const [];
    final label = list.where((i) => i.id == id).map((i) => i.label).firstOrNull;
    ref
        .read(networkProvider.notifier)
        .saveKeystoreCert(
          existingId: widget.existing?.id,
          pattern: _host.text,
          name: _name.text.trim().isEmpty ? (label ?? id) : _name.text.trim(),
          identityId: id,
        );
    Navigator.pop(context);
  }

  Widget _identityList(
    AppLocalizations l,
    KeystoreRelay relay,
    List<KeystoreIdentity>? list,
  ) {
    if (!relay.isSupported) {
      return Text(l.ksUnavailable, key: const Key('ks-unavailable'));
    }
    if (list == null) return Text(l.ksLoading);
    if (list.isEmpty) return Text(l.ksNone, key: const Key('ks-none'));
    return RadioGroup<String>(
      groupValue: _chosen,
      onChanged: (v) => setState(() => _chosen = v),
      child: Column(
        children: [
          for (final i in list)
            RadioListTile<String>(
              key: Key('ks-identity-${i.id}'),
              dense: true,
              value: i.id,
              title: Text(i.label),
              subtitle: i.subject.isEmpty ? null : Text(i.subject),
            ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    final relay = ref.watch(keystoreRelayProvider);
    final list = _identities;
    return AlertDialog(
      title: Text(l.ksTitle),
      content: SizedBox(
        width: 460,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(l.ksHint, style: Theme.of(context).textTheme.bodySmall),
              const SizedBox(height: 8),
              _identityList(l, relay, list),
              TextField(
                key: const Key('ks-host'),
                controller: _host,
                decoration: InputDecoration(labelText: l.nsCertHosts),
              ),
              TextField(
                key: const Key('ks-name'),
                controller: _name,
                decoration: InputDecoration(labelText: l.nsCertName),
              ),
              if (relay.isSupported) ...[
                const SizedBox(height: 8),
                TextField(
                  key: const Key('ks-import-pass'),
                  controller: _pass,
                  obscureText: true,
                  decoration: InputDecoration(labelText: l.ksImportPass),
                ),
                if (defaultTargetPlatform == TargetPlatform.android)
                  Align(
                    alignment: AlignmentDirectional.centerStart,
                    child: TextButton.icon(
                      key: const Key('ks-choose'),
                      icon: const Icon(Icons.verified_user_outlined),
                      label: Text(l.ksChoose),
                      onPressed: _choose,
                    ),
                  ),
                Align(
                  alignment: AlignmentDirectional.centerStart,
                  child: TextButton.icon(
                    key: const Key('ks-import'),
                    icon: const Icon(Icons.file_open_outlined),
                    label: Text(l.ksImport),
                    onPressed: _busy ? null : _import,
                  ),
                ),
              ],
              if (_error != null)
                Text(
                  _error!,
                  key: const Key('ks-error'),
                  style: TextStyle(color: Theme.of(context).colorScheme.error),
                ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: Text(l.ksCancel),
        ),
        FilledButton(
          key: const Key('ks-save'),
          onPressed: _chosen == null ? null : _save,
          child: Text(l.ksSave),
        ),
      ],
    );
  }
}
