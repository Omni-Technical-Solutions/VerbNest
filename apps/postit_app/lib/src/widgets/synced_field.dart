import 'package:flutter/material.dart';

/// A text field that reports edits and also follows [value] when it is
/// changed from elsewhere (e.g. the URL bar and the params table).
class SyncedTextField extends StatefulWidget {
  const SyncedTextField({
    super.key,
    required this.value,
    required this.onChanged,
    this.hint,
    this.label,
    this.maxLines = 1,
    this.obscure = false,
    this.monospace = false,
    this.expands = false,
  });

  final String value;
  final ValueChanged<String> onChanged;
  final String? hint;
  final String? label;
  final int? maxLines;
  final bool obscure;
  final bool monospace;
  final bool expands;

  @override
  State<SyncedTextField> createState() => _SyncedTextFieldState();
}

class _SyncedTextFieldState extends State<SyncedTextField> {
  late final TextEditingController _controller = TextEditingController(
    text: widget.value,
  );

  @override
  void didUpdateWidget(SyncedTextField old) {
    super.didUpdateWidget(old);
    if (widget.value != _controller.text) {
      _controller.value = TextEditingValue(
        text: widget.value,
        selection: TextSelection.collapsed(offset: widget.value.length),
      );
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: _controller,
      onChanged: widget.onChanged,
      obscureText: widget.obscure,
      maxLines: widget.expands ? null : widget.maxLines,
      expands: widget.expands,
      textAlignVertical: widget.expands ? TextAlignVertical.top : null,
      style: widget.monospace ? const TextStyle(fontFamily: 'monospace') : null,
      decoration: InputDecoration(
        isDense: true,
        hintText: widget.hint,
        labelText: widget.label,
      ),
    );
  }
}
