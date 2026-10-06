import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:verbnest_http/verbnest_http.dart';
import 'package:verbnest_storage/verbnest_storage.dart';

import '../state/editor_state.dart';
import '../state/session.dart';
import 'response_view.dart';
import '../../l10n/l10n.dart';

/// Star toggle for a request (FR-COL-004).
class FavouriteButton extends ConsumerStatefulWidget {
  const FavouriteButton({super.key, required this.requestId});

  final String requestId;

  @override
  ConsumerState<FavouriteButton> createState() => _FavouriteButtonState();
}

class _FavouriteButtonState extends ConsumerState<FavouriteButton> {
  @override
  Widget build(BuildContext context) {
    final repo = ref.read(repositoryProvider);
    final fav = repo.isFavourite(widget.requestId);
    return IconButton(
      key: const Key('favourite'),
      tooltip: fav ? context.l10n.exFavRemove : context.l10n.exFavAdd,
      icon: Icon(fav ? Icons.star : Icons.star_border),
      onPressed: () =>
          setState(() => repo.setFavourite(widget.requestId, !fav)),
    );
  }
}

/// Builds the stored form of a response for an example.
({Map<String, Object?> data, Uint8List body}) exampleFromResponse(
  HttpResponseRecord r,
  String method,
) => (
  data: {
    'status': r.status,
    'reason': r.reason,
    'headers': [
      for (final (k, v) in r.headers) [k, v],
    ],
    'request': {'method': method, 'url': r.finalUrl.toString()},
  },
  body: r.body,
);

/// Saved request and response pairs of one request (FR-COL-005).
class ExamplesDialog extends ConsumerStatefulWidget {
  const ExamplesDialog({super.key, required this.requestId});

  final String requestId;

  @override
  ConsumerState<ExamplesDialog> createState() => _ExamplesDialogState();
}

class _ExamplesDialogState extends ConsumerState<ExamplesDialog> {
  String? _selected;

  @override
  Widget build(BuildContext context) {
    final repo = ref.read(repositoryProvider);
    final state = ref.read(editorProvider(widget.requestId));
    final examples = repo.examples(widget.requestId);
    final current = examples.where((e) => e.id == _selected).firstOrNull;
    final response = state.response;
    return AlertDialog(
      title: Text(context.l10n.exTitle),
      content: SizedBox(
        width: 640,
        height: 420,
        child: Row(
          children: [
            SizedBox(
              width: 200,
              child: examples.isEmpty
                  ? Center(
                      key: const Key('no-examples'),
                      child: Text(context.l10n.exEmpty),
                    )
                  : ListView(
                      children: [
                        for (final e in examples)
                          ListTile(
                            key: Key('example-${e.id}'),
                            dense: true,
                            selected: e.id == _selected,
                            title: Text(
                              e.name,
                              overflow: TextOverflow.ellipsis,
                            ),
                            subtitle: Text('${e.data['status'] ?? ''}'),
                            onTap: () => setState(() => _selected = e.id),
                          ),
                      ],
                    ),
            ),
            const VerticalDivider(),
            Expanded(child: _detail(current, repo)),
          ],
        ),
      ),
      actions: [
        TextButton(
          key: const Key('save-example'),
          onPressed: response == null
              ? null
              : () {
                  final ex = exampleFromResponse(response, state.item.method);
                  final id = repo.addExample(
                    widget.requestId,
                    '${response.status} ${response.reason}'.trim(),
                    ex.data,
                    ex.body,
                  );
                  setState(() => _selected = id);
                },
          child: Text(context.l10n.exSave),
        ),
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: Text(context.l10n.exClose),
        ),
      ],
    );
  }

  Widget _detail(ExampleInfo? e, WorkspaceRepository repo) {
    if (e == null) {
      return Center(child: Text(context.l10n.exSelect));
    }
    final headers = [
      for (final h in (e.data['headers'] as List? ?? const []))
        if (h is List && h.length == 2) '${h[0]}: ${h[1]}',
    ];
    final text = utf8.decode(e.body, allowMalformed: true);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                '${e.data['status'] ?? ''} ${e.data['reason'] ?? ''}',
                style: TextStyle(
                  fontWeight: FontWeight.bold,
                  color: statusColor((e.data['status'] as int?) ?? 200),
                ),
              ),
            ),
            IconButton(
              key: const Key('delete-example'),
              tooltip: context.l10n.exDelete,
              icon: const Icon(Icons.delete_outline),
              onPressed: () => setState(() {
                repo.deleteExample(e.id);
                _selected = null;
              }),
            ),
          ],
        ),
        Expanded(
          child: ListView(
            children: [
              SelectableText(
                headers.join('\n'),
                style: const TextStyle(fontFamily: 'monospace', fontSize: 12),
              ),
              const Divider(),
              SelectableText(
                text,
                key: const Key('example-body'),
                style: const TextStyle(fontFamily: 'monospace', fontSize: 12),
              ),
            ],
          ),
        ),
      ],
    );
  }
}
