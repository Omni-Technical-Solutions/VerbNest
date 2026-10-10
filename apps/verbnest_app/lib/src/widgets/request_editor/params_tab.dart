import 'package:material_ui/material_ui.dart';
import 'package:verbnest_core/verbnest_core.dart';

import '../../../l10n/l10n.dart';
import '../../state/editor_state.dart';
import '../kv_editor.dart';
import '../synced_field.dart';

class ParamsTab extends StatelessWidget {
  const ParamsTab({super.key, required this.item, required this.notifier});

  final HttpRequestItem item;
  final EditorNotifier notifier;

  /// Params table edited: rewrite the query to match.
  static HttpRequestItem _withParams(
    HttpRequestItem i,
    List<KeyValue> params,
  ) => i.copyWith(params: params, url: UrlText.withParams(i.url, params));

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Expanded(
          child: KeyValueEditor(
            idPrefix: 'params',
            rows: item.params,
            onChanged: (p) => notifier.edit((i) => _withParams(i, p)),
          ),
        ),
        if (item.pathVars.isNotEmpty) ...[
          Padding(
            padding: const EdgeInsets.all(8),
            child: Text(context.l10n.rePathVars),
          ),
          SizedBox(
            height: 40.0 * item.pathVars.length + 8,
            child: Column(
              children: [
                for (var n = 0; n < item.pathVars.length; n++)
                  _PathVarRow(index: n, item: item, notifier: notifier),
              ],
            ),
          ),
        ],
      ],
    );
  }
}

class _PathVarRow extends StatelessWidget {
  const _PathVarRow({
    required this.index,
    required this.item,
    required this.notifier,
  });

  final int index;
  final HttpRequestItem item;
  final EditorNotifier notifier;

  @override
  Widget build(BuildContext context) {
    final n = index;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8),
      child: Row(
        children: [
          SizedBox(width: 120, child: Text(item.pathVars[n].key)),
          Expanded(
            child: SyncedTextField(
              key: ValueKey('pathvar-$n'),
              value: item.pathVars[n].value,
              hint: context.l10n.reValue,
              onChanged: (v) => notifier.edit((i) {
                final next = [...i.pathVars];
                next[n] = next[n].copyWith(value: v);
                return i.copyWith(pathVars: next);
              }),
            ),
          ),
        ],
      ),
    );
  }
}
