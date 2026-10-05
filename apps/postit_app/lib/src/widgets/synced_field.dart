import 'package:flutter/material.dart';
import 'package:postit_core/postit_core.dart';

import '../state/js_syntax.dart';
import '../state/var_text.dart';

/// Gives text fields below it access to the variables a request resolves
/// against, for highlighting and `{{` completion (FR-VAR-004).
class VariableContext extends InheritedWidget {
  const VariableContext({
    super.key,
    required this.scopes,
    required super.child,
  });

  /// Evaluated on demand so edits made elsewhere are seen.
  final VariableScopes Function() scopes;

  static VariableContext? maybeOf(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<VariableContext>();

  @override
  bool updateShouldNotify(VariableContext old) => true;
}

class _VarController extends TextEditingController {
  _VarController(String text, this.scopes) : super(text: text);

  VariableScopes Function()? scopes;
  bool script = false;

  @override
  TextSpan buildTextSpan({
    required BuildContext context,
    TextStyle? style,
    required bool withComposing,
  }) {
    if (script) return _scriptSpan(context, style);
    final lookup = scopes;
    if (lookup == null || !text.contains('{{')) {
      return super.buildTextSpan(
        context: context,
        style: style,
        withComposing: withComposing,
      );
    }
    final s = lookup();
    final scheme = Theme.of(context).colorScheme;
    final spans = <InlineSpan>[];
    var at = 0;
    for (final t in findTokens(text)) {
      if (t.start > at) spans.add(TextSpan(text: text.substring(at, t.start)));
      final known = s.lookup(t.name) != null;
      spans.add(
        TextSpan(
          text: text.substring(t.start, t.end),
          style: TextStyle(
            color: known ? scheme.primary : scheme.error,
            fontWeight: FontWeight.w600,
            decoration: known ? null : TextDecoration.underline,
            decorationStyle: TextDecorationStyle.wavy,
          ),
        ),
      );
      at = t.end;
    }
    if (at < text.length) spans.add(TextSpan(text: text.substring(at)));
    return TextSpan(style: style, children: spans);
  }

  TextSpan _scriptSpan(BuildContext context, TextStyle? style) {
    final scheme = Theme.of(context).colorScheme;
    TextStyle? colour(JsTokenKind k) => switch (k) {
      JsTokenKind.comment => TextStyle(
        color: scheme.onSurfaceVariant,
        fontStyle: FontStyle.italic,
      ),
      JsTokenKind.string => TextStyle(color: scheme.tertiary),
      JsTokenKind.number => TextStyle(color: scheme.secondary),
      JsTokenKind.keyword => TextStyle(
        color: scheme.primary,
        fontWeight: FontWeight.w600,
      ),
      JsTokenKind.api => TextStyle(
        color: scheme.primary,
        fontWeight: FontWeight.w700,
      ),
    };
    final spans = <InlineSpan>[];
    var at = 0;
    for (final t in tokenizeJs(text)) {
      if (t.start > at) spans.add(TextSpan(text: text.substring(at, t.start)));
      spans.add(
        TextSpan(text: text.substring(t.start, t.end), style: colour(t.kind)),
      );
      at = t.end;
    }
    if (at < text.length) spans.add(TextSpan(text: text.substring(at)));
    return TextSpan(style: style, children: spans);
  }
}

/// A text field that reports edits and also follows [value] when it is
/// changed from elsewhere (e.g. the URL bar and the params table).
///
/// With [variables] it highlights `{{names}}`, shows the resolved value under
/// the caret and offers `{{` completion. [suggestions] are fixed options
/// (header names and the like).
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
    this.variables = false,
    this.script = false,
    this.suggestions = const [],
    this.fontSize,
  });

  final String value;
  final ValueChanged<String> onChanged;
  final String? hint;
  final String? label;
  final int? maxLines;
  final bool obscure;
  final bool monospace;
  final bool expands;
  final bool variables;

  /// Highlight JavaScript and offer `pm.` completion.
  final bool script;
  final List<String> suggestions;
  final double? fontSize;

  @override
  State<SyncedTextField> createState() => _SyncedTextFieldState();
}

class _SyncedTextFieldState extends State<SyncedTextField> {
  late final _VarController _controller = _VarController(widget.value, null);
  final FocusNode _focus = FocusNode();

  @override
  void initState() {
    super.initState();
    _controller.addListener(_refresh);
    _focus.addListener(_refresh);
  }

  void _refresh() {
    if (mounted) setState(() {});
  }

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
    _focus.dispose();
    super.dispose();
  }

  void _apply(String name) {
    final caret = _controller.selection.baseOffset;
    final r = applyCompletion(_controller.text, caret, name);
    _controller.value = TextEditingValue(
      text: r.text,
      selection: TextSelection.collapsed(offset: r.caret),
    );
    widget.onChanged(r.text);
    _focus.requestFocus();
  }

  void _pick(String option) {
    _controller.value = TextEditingValue(
      text: option,
      selection: TextSelection.collapsed(offset: option.length),
    );
    widget.onChanged(option);
    _focus.requestFocus();
  }

  Widget _chips(List<String> names, void Function(String) onTap) => Padding(
    padding: const EdgeInsets.only(top: 2),
    child: Wrap(
      spacing: 4,
      runSpacing: 0,
      children: [
        for (final n in names)
          ActionChip(
            key: ValueKey('suggest-$n'),
            visualDensity: VisualDensity.compact,
            label: Text(n, style: const TextStyle(fontSize: 12)),
            onPressed: () => onTap(n),
          ),
      ],
    ),
  );

  void _applyScript(String name) {
    final r = applyScriptCompletion(
      _controller.text,
      _controller.selection.baseOffset,
      name,
    );
    _controller.value = TextEditingValue(
      text: r.text,
      selection: TextSelection.collapsed(offset: r.caret),
    );
    widget.onChanged(r.text);
    _focus.requestFocus();
  }

  Widget? _info(BuildContext context) {
    if (!_focus.hasFocus) return null;
    final text = _controller.text;
    final caret = _controller.selection.baseOffset;
    if (widget.script) {
      final prefix = scriptPrefix(text, caret);
      final names = prefix == null
          ? const <String>[]
          : scriptCompletions(prefix);
      return names.isEmpty ? null : _chips(names, _applyScript);
    }
    final scheme = Theme.of(context).colorScheme;
    final ctx = widget.variables ? VariableContext.maybeOf(context) : null;
    if (ctx != null && caret >= 0) {
      final s = ctx.scopes();
      final prefix = completionPrefix(text, caret);
      if (prefix != null) {
        final names = matchSuggestionsOrAll(
          s.visible().map((v) => v.variable.key),
          prefix,
        );
        if (names.isNotEmpty) return _chips(names, _apply);
      }
      final t = tokenAt(text, caret);
      if (t != null) {
        final r = s.lookup(t.name);
        return Padding(
          padding: const EdgeInsets.only(top: 2, left: 4),
          child: Text(
            key: const Key('var-info'),
            r == null
                ? '${t.name}: not defined'
                : '${t.name} = ${r.variable.secret ? '••••••' : r.variable.value}'
                      '  (${r.scope.name})',
            style: TextStyle(
              fontSize: 12,
              color: r == null ? scheme.error : scheme.onSurfaceVariant,
            ),
          ),
        );
      }
    }
    if (widget.suggestions.isNotEmpty) {
      final names = matchSuggestions(widget.suggestions, text);
      if (names.isNotEmpty) return _chips(names, _pick);
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    _controller.scopes = widget.variables
        ? VariableContext.maybeOf(context)?.scopes
        : null;
    _controller.script = widget.script;
    final field = TextField(
      controller: _controller,
      focusNode: _focus,
      onChanged: widget.onChanged,
      obscureText: widget.obscure,
      maxLines: widget.expands ? null : widget.maxLines,
      expands: widget.expands,
      textAlignVertical: widget.expands ? TextAlignVertical.top : null,
      style: widget.monospace
          ? TextStyle(fontFamily: 'monospace', fontSize: widget.fontSize)
          : null,
      decoration: InputDecoration(
        isDense: true,
        hintText: widget.hint,
        labelText: widget.label,
      ),
    );
    final info = _info(context);
    if (info == null) return field;
    if (widget.expands) {
      return Column(
        children: [
          Expanded(child: field),
          info,
        ],
      );
    }
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [field, info],
    );
  }
}

/// All names for an empty prefix (up to 8), otherwise the matches.
List<String> matchSuggestionsOrAll(Iterable<String> names, String prefix) =>
    prefix.isEmpty
    ? names.take(8).toList()
    : matchSuggestions(names, prefix, max: 8);
