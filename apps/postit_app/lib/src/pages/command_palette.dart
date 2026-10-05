import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../l10n/l10n.dart';

/// One entry of the command palette (FR-APP-003).
class PaletteEntry {
  const PaletteEntry({
    required this.id,
    required this.title,
    required this.run,
    this.subtitle,
    this.icon,
  });

  final String id;
  final String title;
  final String? subtitle;
  final IconData? icon;
  final VoidCallback run;
}

/// Entries whose title contains every word of [query], best matches first:
/// a title that starts with the query, then word-start matches, then the rest.
List<PaletteEntry> filterPalette(List<PaletteEntry> all, String query) {
  final words = query
      .toLowerCase()
      .split(RegExp(r'\s+'))
      .where((w) => w.isNotEmpty)
      .toList();
  if (words.isEmpty) return all;
  final scored = <(int, PaletteEntry)>[];
  for (final e in all) {
    final t = '${e.title} ${e.subtitle ?? ''}'.toLowerCase();
    if (!words.every(t.contains)) continue;
    final title = e.title.toLowerCase();
    final score = title.startsWith(words.first)
        ? 0
        : title.contains(' ${words.first}')
        ? 1
        : 2;
    scored.add((score, e));
  }
  scored.sort((a, b) => a.$1.compareTo(b.$1));
  return [for (final s in scored) s.$2];
}

/// Fuzzy launcher for commands and requests. Runs the chosen entry after the
/// dialog closes.
Future<void> showCommandPalette(
  BuildContext context,
  List<PaletteEntry> entries,
) async {
  final chosen = await showDialog<PaletteEntry>(
    context: context,
    builder: (_) => _Palette(entries),
  );
  chosen?.run();
}

class _Palette extends StatefulWidget {
  const _Palette(this.entries);

  final List<PaletteEntry> entries;

  @override
  State<_Palette> createState() => _PaletteState();
}

class _PaletteState extends State<_Palette> {
  String _query = '';
  int _index = 0;

  @override
  Widget build(BuildContext context) {
    final shown = filterPalette(widget.entries, _query).take(50).toList();
    if (_index >= shown.length) _index = shown.isEmpty ? 0 : shown.length - 1;
    void choose(int i) {
      if (i < shown.length) Navigator.pop(context, shown[i]);
    }

    return Dialog(
      alignment: Alignment.topCenter,
      insetPadding: const EdgeInsets.only(top: 80, left: 16, right: 16),
      child: SizedBox(
        width: 560,
        height: 420,
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.all(8),
              child: CallbackShortcuts(
                bindings: {
                  const SingleActivator(LogicalKeyboardKey.arrowDown): () =>
                      setState(
                        () => _index = shown.isEmpty
                            ? 0
                            : (_index + 1) % shown.length,
                      ),
                  const SingleActivator(LogicalKeyboardKey.arrowUp): () =>
                      setState(
                        () => _index = shown.isEmpty
                            ? 0
                            : (_index - 1 + shown.length) % shown.length,
                      ),
                },
                child: TextField(
                  key: const Key('palette-input'),
                  autofocus: true,
                  decoration: InputDecoration(
                    prefixIcon: const Icon(Icons.keyboard_command_key),
                    hintText: context.l10n.paletteHint,
                  ),
                  onChanged: (v) => setState(() {
                    _query = v;
                    _index = 0;
                  }),
                  onSubmitted: (_) => choose(_index),
                ),
              ),
            ),
            Expanded(
              child: shown.isEmpty
                  ? Center(
                      key: const Key('palette-empty'),
                      child: Text(context.l10n.paletteNothing),
                    )
                  : ListView.builder(
                      itemCount: shown.length,
                      itemBuilder: (_, i) => ListTile(
                        key: Key('palette-${shown[i].id}'),
                        dense: true,
                        selected: i == _index,
                        leading: Icon(shown[i].icon ?? Icons.http, size: 18),
                        title: Text(shown[i].title),
                        subtitle: shown[i].subtitle == null
                            ? null
                            : Text(shown[i].subtitle!),
                        onTap: () => choose(i),
                      ),
                    ),
            ),
          ],
        ),
      ),
    );
  }
}
