import 'package:material_ui/material_ui.dart';

import '../../l10n/l10n.dart';

class ImportDialog extends StatefulWidget {
  const ImportDialog({super.key});

  @override
  State<ImportDialog> createState() => _ImportDialogState();
}

class _ImportDialogState extends State<ImportDialog> {
  final _controller = TextEditingController();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      // Scrolls when the window is short or the keyboard is up.
      scrollable: true,
      title: Text(context.l10n.sbImport),
      content: SizedBox(
        width: 520,
        child: TextField(
          key: const Key('import-text'),
          controller: _controller,
          autofocus: true,
          maxLines: 12,
          decoration: InputDecoration(hintText: context.l10n.sbImportHint),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: Text(context.l10n.sbCancel),
        ),
        FilledButton(
          key: const Key('import-confirm'),
          onPressed: () => Navigator.pop(context, _controller.text),
          child: Text(context.l10n.sbImport),
        ),
      ],
    );
  }
}
