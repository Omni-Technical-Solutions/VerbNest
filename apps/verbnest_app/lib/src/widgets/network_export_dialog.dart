import 'dart:isolate';
import 'dart:typed_data';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';
import 'package:verbnest_runner/verbnest_runner.dart';

import '../../l10n/l10n.dart';
import '../state/file_port.dart';
import '../state/network_state.dart';
import 'ui/toast.dart';

/// How many PBKDF2 rounds an export uses; tests lower it.
final networkExportRoundsProvider = Provider<int>(
  (ref) => NetworkExport.defaultIterations,
);

/// Asks for a passphrase and saves the network settings, certificates and
/// keys as one locked file for the command line or a CI job (FR-HTTP-013c).
Future<void> showNetworkExport(BuildContext context) => showDialog<void>(
  animationStyle: AnimationStyle.noAnimation,
  context: context,
  builder: (_) => const _ExportDialog(),
);

/// Runs the export in another isolate. A top-level function on purpose: the
/// closure may only reach its own arguments, not the widgets around the caller
/// (they cannot be sent between isolates).
Future<Uint8List> _lock(NetworkConfig config, String pass, int rounds) =>
    Isolate.run(() => NetworkExport.encrypt(config, pass, iterations: rounds));

class _ExportDialog extends ConsumerStatefulWidget {
  const _ExportDialog();

  @override
  ConsumerState<_ExportDialog> createState() => _ExportDialogState();
}

class _ExportDialogState extends ConsumerState<_ExportDialog> {
  final _pass = TextEditingController();
  final _again = TextEditingController();
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _pass.dispose();
    _again.dispose();
    super.dispose();
  }

  Future<void> _export() async {
    final l = context.l10n;
    if (_pass.text.isEmpty || _pass.text != _again.text) {
      setState(() => _error = l.nsExportMismatch);
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    final config = ref.read(networkProvider);
    final rounds = ref.read(networkExportRoundsProvider);
    final pass = _pass.text;
    final files = ref.read(filePortProvider);
    final messenger = Navigator.of(context);
    final saved = l.nsExportSaved;
    try {
      // The key derivation is slow on purpose; keep it off the UI isolate.
      final bytes = await _lock(config, pass, rounds);
      final ok = await files.save(
        'verbnest-network.json',
        bytes,
        mime: 'application/json',
      );
      if (!mounted) return;
      messenger.pop();
      if (ok && context.mounted) showToast(context, saved);
    } on NetworkExportError catch (e) {
      if (mounted) setState(() => _error = e.message);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    return AlertDialog(
      scrollable: true,
      title: Text(l.nsExportTitle),
      content: SizedBox(
        width: 420,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(l.nsExportHint, style: Theme.of(context).textTheme.bodySmall),
            TextField(
              key: const Key('export-pass'),
              controller: _pass,
              obscureText: true,
              enabled: !_busy,
              decoration: InputDecoration(labelText: l.nsExportPass),
            ),
            TextField(
              key: const Key('export-pass2'),
              controller: _again,
              obscureText: true,
              enabled: !_busy,
              decoration: InputDecoration(labelText: l.nsExportPass2),
            ),
            if (_error != null)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Text(
                  _error!,
                  key: const Key('export-error'),
                  style: TextStyle(color: Theme.of(context).colorScheme.error),
                ),
              ),
            if (_busy)
              Padding(
                padding: const EdgeInsets.only(top: 12),
                child: Row(
                  children: [
                    const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    ),
                    const SizedBox(width: 8),
                    Expanded(child: Text(l.nsExportBusy)),
                  ],
                ),
              ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: _busy ? null : () => Navigator.pop(context),
          child: Text(l.nsCancel),
        ),
        FilledButton(
          key: const Key('export-confirm'),
          onPressed: _busy ? null : _export,
          child: Text(l.nsExport),
        ),
      ],
    );
  }
}
