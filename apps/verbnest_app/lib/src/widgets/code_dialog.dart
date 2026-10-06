import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:verbnest_import/verbnest_import.dart';

import '../state/import_actions.dart';
import '../state/session.dart';
import '../state/variables.dart';
import '../../l10n/l10n.dart';

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
      title: Text(context.l10n.codeTitle),
      content: SizedBox(
        width: 560,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            DropdownMenu<CodeLanguage>(
              key: const Key('code-language'),
              initialSelection: _language,
              expandedInsets: EdgeInsets.zero,
              requestFocusOnTap: false,
              dropdownMenuEntries: [
                for (final l in CodeLanguage.values)
                  DropdownMenuEntry(value: l, label: l.label),
              ],
              onSelected: (l) => setState(() => _language = l ?? _language),
            ),
            SwitchListTile(
              key: const Key('code-resolve'),
              contentPadding: EdgeInsets.zero,
              title: Text(context.l10n.codeFillVariables),
              subtitle: Text(context.l10n.codeSecretsWarning),
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
                .showSnackBar(SnackBar(content: Text(context.l10n.codeCopied)));
          },
          child: Text(context.l10n.copy),
        ),
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: Text(context.l10n.close),
        ),
      ],
    );
  }
}
