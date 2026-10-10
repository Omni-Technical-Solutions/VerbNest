import 'package:material_ui/material_ui.dart';
import 'package:verbnest_core/verbnest_core.dart';

import '../state/var_text.dart';
import 'synced_field.dart';
import '../../l10n/l10n.dart';
import '../theme.dart';

/// Editable key/value table used for params, headers and form bodies.
class KeyValueEditor extends StatefulWidget {
  const KeyValueEditor({
    super.key,
    required this.rows,
    required this.onChanged,
    this.idPrefix = 'kv',
    this.keySuggestions = const [],
    this.valueSuggestions = const {},
    this.allowBulk = true,
    this.onPickFile,
  });

  final List<KeyValue> rows;
  final ValueChanged<List<KeyValue>> onChanged;
  final String idPrefix;

  /// Fixed options offered for the key (e.g. header names).
  final List<String> keySuggestions;

  /// Options for the value, by lower-case key (e.g. `content-type`).
  final Map<String, List<String>> valueSuggestions;

  /// Bulk edit rewrites rows from text, so it is off where rows carry more
  /// than key and value (form-data file parts).
  final bool allowBulk;

  /// When set, rows can switch between text and file. Returns the row with
  /// the chosen file, or null when cancelled.
  final Future<KeyValue?> Function(KeyValue row)? onPickFile;

  @override
  State<KeyValueEditor> createState() => _KeyValueEditorState();
}

class _KeyValueEditorState extends State<KeyValueEditor> {
  bool _bulk = false;
  late final TextEditingController _bulkController = TextEditingController();

  List<KeyValue> get rows => widget.rows;
  String get idPrefix => widget.idPrefix;
  ValueChanged<List<KeyValue>> get onChanged => widget.onChanged;

  @override
  void dispose() {
    _bulkController.dispose();
    super.dispose();
  }

  void _toggleBulk() {
    setState(() {
      _bulk = !_bulk;
      if (_bulk) _bulkController.text = formatBulk(rows);
    });
  }

  Widget _fileCell(int i) {
    final value = rows[i].value;
    final slash = value.indexOf('/');
    final label = value.isEmpty
        ? context.l10n.kvChooseFile
        : (slash < 0 ? value : value.substring(slash + 1));
    return Align(
      alignment: AlignmentDirectional.centerStart,
      child: OutlinedButton.icon(
        key: ValueKey('$idPrefix-file-$i'),
        icon: const Icon(Icons.upload_file, size: 18),
        label: Text(label, overflow: TextOverflow.ellipsis),
        onPressed: () async {
          final next = await widget.onPickFile!(rows[i]);
          if (next != null && mounted) _set(i, next);
        },
      ),
    );
  }

  Widget _bulkEditor() => ListView(
    padding: const EdgeInsets.all(8),
    children: [
      Align(
        alignment: AlignmentDirectional.centerEnd,
        child: TextButton(
          key: Key('$idPrefix-table'),
          onPressed: _toggleBulk,
          child: Text(context.l10n.kvTableEdit),
        ),
      ),
      TextField(
        key: Key('$idPrefix-bulk'),
        controller: _bulkController,
        minLines: 6,
        maxLines: null,
        style: monoStyle(),
        decoration: InputDecoration(
          isDense: true,
          hintText: context.l10n.kvBulkHint,
        ),
        onChanged: (t) => onChanged(parseBulk(t)),
      ),
    ],
  );

  void _set(int i, KeyValue row) {
    final next = [...rows];
    next[i] = row;
    onChanged(next);
  }

  @override
  Widget build(BuildContext context) {
    if (_bulk) return _bulkEditor();
    return ListView(
      padding: const EdgeInsets.all(8),
      children: [
        if (widget.allowBulk)
          Align(
            alignment: AlignmentDirectional.centerEnd,
            child: TextButton(
              key: Key('$idPrefix-bulk-toggle'),
              onPressed: _toggleBulk,
              child: Text(context.l10n.kvBulkEdit),
            ),
          ),
        for (var i = 0; i < rows.length; i++) _row(i),
        Align(
          alignment: AlignmentDirectional.centerStart,
          child: TextButton.icon(
            key: Key('$idPrefix-add'),
            icon: const Icon(Icons.add, size: 18),
            label: Text(context.l10n.add),
            onPressed: () => onChanged([...rows, const KeyValue(key: '')]),
          ),
        ),
      ],
    );
  }

  Widget _row(int i) {
    return _RowIn(
      key: ValueKey('$idPrefix-row-$i'),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 2),
        // Two fields and two buttons leave each field about 90 dp on a phone
        // under 360 dp: stack the value under the key there.
        child: LayoutBuilder(
          builder: (context, c) =>
              c.maxWidth < 360 ? _stackedRow(i) : _wideRow(i),
        ),
      ),
    );
  }

  Widget _enabledBox(int i) => Checkbox(
    value: rows[i].enabled,
    onChanged: (v) => _set(i, rows[i].copyWith(enabled: v)),
  );

  Widget _keyField(int i) => SyncedTextField(
    key: ValueKey('$idPrefix-key-$i'),
    value: rows[i].key,
    hint: context.l10n.kvKey,
    variables: true,
    suggestions: widget.keySuggestions,
    onChanged: (v) => _set(i, rows[i].copyWith(key: v)),
  );

  Widget _removeButton(int i) => IconButton(
    tooltip: context.l10n.remove,
    icon: const Icon(Icons.close, size: 18),
    onPressed: () => onChanged([...rows]..removeAt(i)),
  );

  Widget _wideRow(int i) => Row(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      _enabledBox(i),
      Expanded(child: _keyField(i)),
      const SizedBox(width: 8),
      Expanded(child: _valueCell(i)),
      if (widget.onPickFile != null) _typeToggle(i),
      _removeButton(i),
    ],
  );

  Widget _stackedRow(int i) => Column(
    children: [
      Row(
        children: [
          _enabledBox(i),
          Expanded(child: _keyField(i)),
          if (widget.onPickFile != null) _typeToggle(i),
          _removeButton(i),
        ],
      ),
      // Lined up under the key field (a checkbox is 48 dp wide).
      Padding(
        padding: const EdgeInsetsDirectional.only(start: 48, bottom: 6),
        child: _valueCell(i),
      ),
    ],
  );

  Widget _valueCell(int i) {
    if (rows[i].type == KeyValueType.file) return _fileCell(i);
    return SyncedTextField(
      key: ValueKey('$idPrefix-value-$i'),
      value: rows[i].value,
      hint: context.l10n.kvValue,
      variables: true,
      suggestions:
          widget.valueSuggestions[rows[i].key.toLowerCase()] ?? const [],
      onChanged: (v) => _set(i, rows[i].copyWith(value: v)),
    );
  }

  Widget _typeToggle(int i) {
    final isFile = rows[i].type == KeyValueType.file;
    return IconButton(
      key: ValueKey('$idPrefix-type-$i'),
      tooltip: isFile
          ? context.l10n.kvSwitchToText
          : context.l10n.kvSwitchToFile,
      icon: Icon(isFile ? Icons.attach_file : Icons.text_fields, size: 18),
      onPressed: () => _set(
        i,
        rows[i].copyWith(
          type: isFile ? KeyValueType.text : KeyValueType.file,
          value: '',
        ),
      ),
    );
  }
}

/// Rows fade and slide in when the table grows; existing rows are not
/// re-animated because the key moves with the row's position.
class _RowIn extends StatefulWidget {
  const _RowIn({super.key, required this.child});

  final Widget child;

  @override
  State<_RowIn> createState() => _RowInState();
}

class _RowInState extends State<_RowIn> {
  bool _shown = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) setState(() => _shown = true);
    });
  }

  @override
  Widget build(BuildContext context) {
    final d = Motion.of(context, Motion.base);
    return AnimatedOpacity(
      opacity: _shown ? 1 : 0,
      duration: d,
      curve: Motion.curve,
      child: AnimatedSlide(
        offset: _shown ? Offset.zero : const Offset(0, -0.1),
        duration: d,
        curve: Motion.curve,
        child: widget.child,
      ),
    );
  }
}
