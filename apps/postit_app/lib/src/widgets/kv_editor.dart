import 'package:flutter/material.dart';
import 'package:postit_core/postit_core.dart';

import '../state/var_text.dart';
import 'synced_field.dart';

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
        ? 'Choose file…'
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
          child: const Text('Table edit'),
        ),
      ),
      TextField(
        key: Key('$idPrefix-bulk'),
        controller: _bulkController,
        minLines: 6,
        maxLines: null,
        style: const TextStyle(fontFamily: 'monospace'),
        decoration: const InputDecoration(
          isDense: true,
          hintText: 'key: value (one per line, // to disable)',
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
              child: const Text('Bulk edit'),
            ),
          ),
        for (var i = 0; i < rows.length; i++)
          Padding(
            key: ValueKey('$idPrefix-row-$i'),
            padding: const EdgeInsets.symmetric(vertical: 2),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Checkbox(
                  value: rows[i].enabled,
                  onChanged: (v) => _set(i, rows[i].copyWith(enabled: v)),
                ),
                Expanded(
                  child: SyncedTextField(
                    key: ValueKey('$idPrefix-key-$i'),
                    value: rows[i].key,
                    hint: 'Key',
                    variables: true,
                    suggestions: widget.keySuggestions,
                    onChanged: (v) => _set(i, rows[i].copyWith(key: v)),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: rows[i].type == KeyValueType.file
                      ? _fileCell(i)
                      : SyncedTextField(
                          key: ValueKey('$idPrefix-value-$i'),
                          value: rows[i].value,
                          hint: 'Value',
                          variables: true,
                          suggestions:
                              widget.valueSuggestions[rows[i].key
                                  .toLowerCase()] ??
                              const [],
                          onChanged: (v) => _set(i, rows[i].copyWith(value: v)),
                        ),
                ),
                if (widget.onPickFile != null)
                  IconButton(
                    key: ValueKey('$idPrefix-type-$i'),
                    tooltip: rows[i].type == KeyValueType.file
                        ? 'File (switch to text)'
                        : 'Text (switch to file)',
                    icon: Icon(
                      rows[i].type == KeyValueType.file
                          ? Icons.attach_file
                          : Icons.text_fields,
                      size: 18,
                    ),
                    onPressed: () => _set(
                      i,
                      rows[i].copyWith(
                        type: rows[i].type == KeyValueType.file
                            ? KeyValueType.text
                            : KeyValueType.file,
                        value: '',
                      ),
                    ),
                  ),
                IconButton(
                  tooltip: 'Remove',
                  icon: const Icon(Icons.close, size: 18),
                  onPressed: () => onChanged([...rows]..removeAt(i)),
                ),
              ],
            ),
          ),
        Align(
          alignment: AlignmentDirectional.centerStart,
          child: TextButton.icon(
            key: Key('$idPrefix-add'),
            icon: const Icon(Icons.add, size: 18),
            label: const Text('Add'),
            onPressed: () => onChanged([...rows, const KeyValue(key: '')]),
          ),
        ),
      ],
    );
  }
}
