import 'package:flutter/material.dart';
import 'package:postit_core/postit_core.dart';

import 'synced_field.dart';

/// Editable key/value table used for params, headers and form bodies.
class KeyValueEditor extends StatelessWidget {
  const KeyValueEditor({
    super.key,
    required this.rows,
    required this.onChanged,
    this.idPrefix = 'kv',
  });

  final List<KeyValue> rows;
  final ValueChanged<List<KeyValue>> onChanged;
  final String idPrefix;

  void _set(int i, KeyValue row) {
    final next = [...rows];
    next[i] = row;
    onChanged(next);
  }

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.all(8),
      children: [
        for (var i = 0; i < rows.length; i++)
          Padding(
            key: ValueKey('$idPrefix-row-$i'),
            padding: const EdgeInsets.symmetric(vertical: 2),
            child: Row(
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
                    onChanged: (v) => _set(i, rows[i].copyWith(key: v)),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: SyncedTextField(
                    key: ValueKey('$idPrefix-value-$i'),
                    value: rows[i].value,
                    hint: 'Value',
                    onChanged: (v) => _set(i, rows[i].copyWith(value: v)),
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
          alignment: Alignment.centerLeft,
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
