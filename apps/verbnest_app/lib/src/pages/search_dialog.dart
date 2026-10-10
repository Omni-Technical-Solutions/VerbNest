import 'package:material_ui/material_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:verbnest_storage/verbnest_storage.dart';

import '../state/session.dart';
import '../state/tree_state.dart';

/// Opens workspace search; on a pick, reveals it in the tree and opens a
/// request in a tab. Returns the chosen hit.
Future<SearchHit?> runSearch(BuildContext context, WidgetRef ref) async {
  final session = ref.read(sessionProvider);
  session.searchIndex.rebuild();
  final hit = await showDialog<SearchHit>(
    context: context,
    builder: (_) => _SearchDialog(index: session.searchIndex),
  );
  if (hit == null) return null;
  final repo = session.repo;
  final expanded = ref.read(expandedProvider.notifier);
  for (final a in repo.ancestors(hit.id)) {
    expanded.expand(a);
  }
  if (hit.kind == NodeKind.request) {
    ref.read(tabsProvider.notifier).open(hit.id);
  } else {
    expanded.expand(hit.id);
  }
  return hit;
}

class _SearchDialog extends StatefulWidget {
  const _SearchDialog({required this.index});

  final SearchIndex index;

  @override
  State<_SearchDialog> createState() => _SearchDialogState();
}

class _SearchDialogState extends State<_SearchDialog> {
  List<SearchHit> _hits = const [];

  @override
  Widget build(BuildContext context) {
    return Dialog(
      alignment: Alignment.topCenter,
      insetPadding: const EdgeInsets.only(top: 64, left: 16, right: 16),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 560, maxHeight: 460),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsets.all(12),
              child: TextField(
                key: const Key('search-input'),
                autofocus: true,
                decoration: const InputDecoration(
                  prefixIcon: Icon(Icons.search),
                  hintText: 'Search names, URLs, headers and bodies',
                ),
                onChanged: (q) =>
                    setState(() => _hits = widget.index.search(q)),
                onSubmitted: (_) {
                  if (_hits.isNotEmpty) Navigator.pop(context, _hits.first);
                },
              ),
            ),
            Flexible(
              child: ListView(
                shrinkWrap: true,
                children: [
                  for (final h in _hits)
                    ListTile(
                      key: Key('hit-${h.id}'),
                      dense: true,
                      leading: SizedBox(
                        width: 44,
                        child: Text(
                          h.kind == NodeKind.request ? (h.method ?? 'GET') : '',
                          style: const TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                      title: Text(h.name),
                      subtitle: Text(
                        [
                          if (h.path.isNotEmpty) h.path.join(' / '),
                          if (h.url != null && h.url!.isNotEmpty) h.url!,
                        ].join('   '),
                        overflow: TextOverflow.ellipsis,
                      ),
                      onTap: () => Navigator.pop(context, h),
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
