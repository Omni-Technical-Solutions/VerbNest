import 'dart:async';

import 'package:flutter/material.dart';
import 'package:verbnest_http/verbnest_http.dart';

import '../../l10n/l10n.dart';
import '../theme.dart';

/// Live message log for a WebSocket or SSE connection.
class RealtimeDialog extends StatefulWidget {
  const RealtimeDialog({
    super.key,
    required this.connect,
    required this.sse,
    required this.title,
    this.onSave,
  });

  final Future<RealtimeConnection> Function() connect;
  final bool sse;
  final String title;

  /// Saves the transcript; the button shows only when this is set.
  final Future<void> Function(String transcript)? onSave;

  @override
  State<RealtimeDialog> createState() => _RealtimeDialogState();
}

class _RealtimeDialogState extends State<RealtimeDialog> {
  final _log = <RealtimeMessage>[];
  final _input = TextEditingController();
  RealtimeConnection? _conn;
  StreamSubscription<RealtimeMessage>? _sub;
  String? _error;
  bool _connecting = false;
  bool _open = false;
  bool _hex = false;

  Future<void> _connect() async {
    setState(() {
      _connecting = true;
      _error = null;
    });
    try {
      final c = await widget.connect();
      if (!mounted) {
        unawaited(c.close());
        return;
      }
      _conn = c;
      _sub = c.messages.listen((m) {
        if (mounted) setState(() => _log.add(m));
      });
      setState(() => _open = true);
      unawaited(
        c.done.whenComplete(() {
          if (mounted) setState(() => _open = false);
        }),
      );
    } on FormatException catch (e) {
      setState(() => _error = e.message);
    } on Object catch (e) {
      setState(() => _error = '$e');
    } finally {
      if (mounted) setState(() => _connecting = false);
    }
  }

  Future<void> _send() async {
    final text = _input.text;
    if (text.isEmpty || _conn == null || !_conn!.canSend) return;
    try {
      await _conn!.send(_hex ? parseHexBytes(text) : text);
      _input.clear();
    } on FormatException catch (e) {
      setState(() => _error = e.message);
    } on Object catch (e) {
      setState(() => _error = '$e');
    }
  }

  @override
  void dispose() {
    unawaited(_sub?.cancel());
    unawaited(_conn?.close());
    _input.dispose();
    super.dispose();
  }

  String _prefix(RealtimeMessage m) => switch (m.direction) {
    RealtimeDirection.sent => '→ ',
    RealtimeDirection.received => '← ${m.event == null ? '' : '[${m.event}] '}',
    RealtimeDirection.system => '• ',
  };

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(widget.title),
      content: SizedBox(
        width: 560,
        height: 380,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _buildToolbar(context),
            if (_error != null) _buildError(context),
            const SizedBox(height: 8),
            Expanded(child: _buildLog(context)),
            if (!widget.sse) _buildInputRow(context),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text(context.l10n.close),
        ),
      ],
    );
  }

  Widget _buildToolbar(BuildContext context) {
    return Row(
      children: [
        if (_open)
          FilledButton.tonal(
            key: const Key('rt-disconnect'),
            onPressed: () => unawaited(_conn?.close()),
            child: Text(context.l10n.rtDisconnect),
          )
        else
          FilledButton(
            key: const Key('rt-connect'),
            onPressed: _connecting ? null : _connect,
            child: Text(
              _connecting ? context.l10n.rtConnecting : context.l10n.rtConnect,
            ),
          ),
        const SizedBox(width: 8),
        TextButton(
          key: const Key('rt-clear'),
          onPressed: () => setState(_log.clear),
          child: Text(context.l10n.rtClear),
        ),
        if (widget.onSave != null)
          TextButton(
            key: const Key('rt-save'),
            onPressed: _log.isEmpty
                ? null
                : () => widget.onSave!(formatRealtimeLog(_log)),
            child: Text(context.l10n.rtSave),
          ),
      ],
    );
  }

  Widget _buildError(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 8),
      child: Text(
        _error!,
        key: const Key('rt-error'),
        style: TextStyle(color: Theme.of(context).colorScheme.error),
      ),
    );
  }

  Widget _buildLog(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        border: Border.all(color: Theme.of(context).dividerColor),
      ),
      child: ListView.builder(
        key: const Key('rt-log'),
        itemCount: _log.length,
        itemBuilder: (_, i) {
          final m = _log[i];
          return Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
            child: SelectableText(
              '${_prefix(m)}${m.text}',
              style: monoStyle(fontSize: 12),
            ),
          );
        },
      ),
    );
  }

  Widget _buildInputRow(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: TextField(
            key: const Key('rt-input'),
            controller: _input,
            enabled: _open,
            decoration: InputDecoration(
              hintText: _hex
                  ? context.l10n.rtHexHint
                  : context.l10n.rtMessageHint,
              isDense: true,
            ),
            onSubmitted: (_) => _send(),
          ),
        ),
        Checkbox(
          key: const Key('rt-hex'),
          value: _hex,
          onChanged: (v) => setState(() => _hex = v ?? false),
        ),
        Text(context.l10n.rtHex),
        IconButton(
          key: const Key('rt-send'),
          tooltip: context.l10n.rtSendTooltip,
          onPressed: _open ? _send : null,
          icon: const Icon(Icons.send),
        ),
      ],
    );
  }
}
