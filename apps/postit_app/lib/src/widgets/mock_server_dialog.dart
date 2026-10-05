import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:postit_runner/postit_runner.dart';

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
      setState(() => _error = 'Port must be 0-65535');
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
      setState(() => _error = 'Cannot listen on port $port: $e');
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
      title: const Text('Mock server'),
      content: SizedBox(
        width: 480,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (_routes.isEmpty)
              const Text(
                'No request here has a saved example. Save a response as an '
                'example first.',
                key: Key('mock-empty'),
              )
            else ...[
              Row(
                children: [
                  SizedBox(
                    width: 90,
                    child: TextField(
                      key: const Key('mock-port'),
                      controller: _port,
                      enabled: running == null,
                      decoration: const InputDecoration(labelText: 'Port'),
                      keyboardType: TextInputType.number,
                    ),
                  ),
                  const SizedBox(width: 12),
                  if (running == null)
                    FilledButton(
                      key: const Key('mock-start'),
                      onPressed: _start,
                      child: const Text('Start'),
                    )
                  else
                    FilledButton.tonal(
                      key: const Key('mock-stop'),
                      onPressed: _stop,
                      child: const Text('Stop'),
                    ),
                ],
              ),
              if (running != null)
                Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: SelectableText(
                    'Serving on http://127.0.0.1:${running.port}',
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
                          '${r.requestName}, ${r.examples.length} example'
                          '${r.examples.length == 1 ? '' : 's'}',
                        ),
                      ),
                  ],
                ),
              ),
              const Text(
                'Send an X-PostIt-Example header to pick an example by name.',
                style: TextStyle(fontSize: 12),
              ),
            ],
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Close'),
        ),
      ],
    );
  }
}
