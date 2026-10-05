import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:postit_import/postit_import.dart';

import '../state/import_actions.dart';
import '../state/session.dart';
import '../state/variables.dart';

/// Shows a request as code in a chosen language (FR-IO-003).
class CodeDialog extends ConsumerStatefulWidget {
  const CodeDialog({super.key, required this.requestId});

  final String requestId;

  @override
  ConsumerState<CodeDialog> createState() => _CodeDialogState();
}

class _CodeDialogState extends ConsumerState<CodeDialog> {
  var _language = CodeLanguage.curl;
  var _resolve = false;

  @override
  Widget build(BuildContext context) {
    final code = requestAsCode(
      ref.read(sessionProvider),
      widget.requestId,
      _language,
      resolve: _resolve,
      envId: ref.read(activeEnvProvider),
    );
    return AlertDialog(
      title: const Text('Generate code'),
      content: SizedBox(
        width: 560,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            DropdownButton<CodeLanguage>(
              key: const Key('code-language'),
              value: _language,
              items: [
                for (final l in CodeLanguage.values)
                  DropdownMenuItem(value: l, child: Text(l.label)),
              ],
              onChanged: (l) => setState(() => _language = l ?? _language),
            ),
            SwitchListTile(
              key: const Key('code-resolve'),
              contentPadding: EdgeInsets.zero,
              title: const Text('Fill in variable values'),
              subtitle: const Text('Secret values will appear in the code'),
              value: _resolve,
              onChanged: (v) => setState(() => _resolve = v),
            ),
            Flexible(
              child: Container(
                width: double.infinity,
                padding: const EdgeInsets.all(8),
                color: Theme.of(context).colorScheme.surfaceContainerHighest,
                child: SingleChildScrollView(
                  child: SelectableText(
                    code,
                    key: const Key('code-text'),
                    style: const TextStyle(
                      fontFamily: 'monospace',
                      fontSize: 12,
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          key: const Key('code-copy'),
          onPressed: () async {
            await Clipboard.setData(ClipboardData(text: code));
            if (!context.mounted) return;
            ScaffoldMessenger.of(context)
                .showSnackBar(const SnackBar(content: Text('Code copied')));
          },
          child: const Text('Copy'),
        ),
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Close'),
        ),
      ],
    );
  }
}
