import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:postit_runner/postit_runner.dart';

import '../../l10n/l10n.dart';
import '../state/session.dart';
import '../state/variables.dart';

/// Serves the saved examples of a collection or folder on localhost while
/// the dialog is open (FR-COL-005).
class MockServerDialog extends ConsumerStatefulWidget {
  const MockServerDialog({super.key, required this.containerId});

  final String containerId;

  @override
  ConsumerState<MockServerDialog> createState() => _MockServerDialogState();
}

class _MockServerDialogState extends ConsumerState<MockServerDialog> {
  final _port = TextEditingController(text: '3000');
  late final List<MockRoute> _routes;
  MockServer? _server;
  String? _error;

  @override
  void initState() {
    super.initState();
    _routes = MockServer.routesFor(
      ref.read(sessionProvider).repo,
      widget.containerId,
      envId: ref.read(activeEnvProvider),
    );
  }

  Future<void> _start() async {
    final port = int.tryParse(_port.text.trim());
    if (port == null || port < 0 || port > 65535) {
      setState(() => _error = context.l10n.mockPortInvalid);
      return;
    }
    try {
      final s = await MockServer.start(_routes, port: port);
      if (!mounted) {
        unawaited(s.close());
        return;
      }
      setState(() {
        _server = s;
        _error = null;
      });
    } on Object catch (e) {
      setState(() => _error = context.l10n.mockListenFailed(port, '$e'));
    }
  }

  Future<void> _stop() async {
    final s = _server;
    setState(() => _server = null);
    await s?.close();
  }

  @override
  void dispose() {
    unawaited(_server?.close());
    _port.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final running = _server;
    return AlertDialog(
      title: Text(context.l10n.mockTitle),
      content: SizedBox(
        width: 480,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (_routes.isEmpty)
              Text(context.l10n.mockEmpty, key: const Key('mock-empty'))
            else ...[
              Row(
                children: [
                  SizedBox(
                    width: 90,
                    child: TextField(
                      key: const Key('mock-port'),
                      controller: _port,
                      enabled: running == null,
                      decoration: InputDecoration(
                        labelText: context.l10n.mockPort,
                      ),
                      keyboardType: TextInputType.number,
                    ),
                  ),
                  const SizedBox(width: 12),
                  if (running == null)
                    FilledButton(
                      key: const Key('mock-start'),
                      onPressed: _start,
                      child: Text(context.l10n.mockStart),
                    )
                  else
                    FilledButton.tonal(
                      key: const Key('mock-stop'),
                      onPressed: _stop,
                      child: Text(context.l10n.mockStop),
                    ),
                ],
              ),
              if (running != null)
                Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: SelectableText(
                    context.l10n.mockServing(
                      'http://127.0.0.1:${running.port}',
                    ),
                    key: const Key('mock-url'),
                  ),
                ),
              if (_error != null)
                Text(
                  _error!,
                  key: const Key('mock-error'),
                  style: TextStyle(color: Theme.of(context).colorScheme.error),
                ),
              const SizedBox(height: 12),
              Flexible(
                child: ListView(
                  shrinkWrap: true,
                  children: [
                    for (final r in _routes)
                      ListTile(
                        dense: true,
                        title: Text('${r.method} ${r.path}'),
                        subtitle: Text(
                          context.l10n.mockRouteSubtitle(
                            r.requestName,
                            r.examples.length,
                          ),
                        ),
                      ),
                  ],
                ),
              ),
              Text(
                context.l10n.mockHeaderHint,
                style: const TextStyle(fontSize: 12),
              ),
            ],
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
}
