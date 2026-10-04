import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:postit_http/postit_http.dart';

import '../state/cookies.dart';
import '../state/editor_state.dart';
import 'code_view.dart';

String formatBytes(int n) {
  if (n < 1024) return '$n B';
  if (n < 1024 * 1024) return '${(n / 1024).toStringAsFixed(1)} KB';
  return '${(n / 1024 / 1024).toStringAsFixed(1)} MB';
}

/// Pretty-prints JSON for display only; the stored bytes are untouched.
String prettyBody(HttpResponseRecord r) {
  final text = r.bodyText;
  final type = r.header('content-type')?.toLowerCase() ?? '';
  if (type.contains('json')) {
    try {
      return const JsonEncoder.withIndent('  ').convert(jsonDecode(text));
    } on FormatException {
      return text;
    }
  }
  return text;
}

bool isImageResponse(HttpResponseRecord r) {
  final t = (r.header('content-type') ?? '').toLowerCase();
  return t.startsWith('image/') && !t.contains('svg');
}

/// Decoded size, plus the size on the wire when compression changed it.
String sizeLabel(HttpResponseRecord r) => r.wireBodySize == r.body.length
    ? formatBytes(r.body.length)
    : '${formatBytes(r.body.length)} (${formatBytes(r.wireBodySize)} on the wire)';

Color statusColor(int status) {
  if (status >= 500) return Colors.red.shade700;
  if (status >= 400) return Colors.orange.shade800;
  if (status >= 300) return Colors.blue.shade700;
  return Colors.green.shade700;
}

/// Status line plus Body / Cookies / Headers / Sent tabs (FR-RES-001..).
class ResponseView extends StatefulWidget {
  const ResponseView({
    super.key,
    required this.state,
    this.onSave,
    this.saveLabel = 'Save',
    this.codeFontSize = 13,
  });

  final EditorState state;

  /// Saves or shares the response body; the button shows only when set.
  final VoidCallback? onSave;
  final String saveLabel;
  final double codeFontSize;

  @override
  State<ResponseView> createState() => _ResponseViewState();
}

class _ResponseViewState extends State<ResponseView> {
  bool _pretty = true;
  bool _preview = false;
  String _query = '';

  @override
  Widget build(BuildContext context) {
    final state = widget.state;
    if (state.sending) {
      return const Center(child: CircularProgressIndicator());
    }
    if (state.error != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Text(
            state.error!,
            key: const Key('response-error'),
            style: TextStyle(color: Theme.of(context).colorScheme.error),
          ),
        ),
      );
    }
    final r = state.response;
    if (r == null) {
      return const Center(child: Text('Send the request to see a response'));
    }
    final cookies = [
      for (final (k, v) in r.headers)
        if (k.toLowerCase() == 'set-cookie') ?parseSetCookie(v),
    ];
    return DefaultTabController(
      length: 4,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.all(8),
            child: Wrap(
              spacing: 12,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                Text(
                  '${r.status} ${r.reason}',
                  key: const Key('response-status'),
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    color: statusColor(r.status),
                  ),
                ),
                Text('${r.timings.total.inMilliseconds} ms'),
                Text(sizeLabel(r)),
                if (widget.onSave != null)
                  TextButton.icon(
                    key: const Key('response-save'),
                    icon: Icon(
                      widget.saveLabel == 'Share'
                          ? Icons.ios_share
                          : Icons.save_alt,
                      size: 18,
                    ),
                    label: Text(widget.saveLabel),
                    onPressed: widget.onSave,
                  ),
              ],
            ),
          ),
          TabBar(
            tabs: [
              const Tab(text: 'Body'),
              Tab(
                text: cookies.isEmpty
                    ? 'Cookies'
                    : 'Cookies (${cookies.length})',
              ),
              const Tab(text: 'Headers'),
              const Tab(text: 'Sent'),
            ],
          ),
          Expanded(
            child: TabBarView(
              children: [
                _body(r),
                _cookies(cookies),
                _headers(r),
                _scroll(_sentText(state), key: const Key('response-sent')),
              ],
            ),
          ),
        ],
      ),
    );
  }

  static String _sentText(EditorState s) {
    final head = s.maskedSentHead ?? '';
    final body = s.maskedSentBody ?? '';
    return body.isEmpty ? head : '${head.trimRight()}\n\n$body';
  }

  Widget _headers(HttpResponseRecord r) => ListView(
    key: const Key('response-headers'),
    children: [
      for (var i = 0; i < r.headers.length; i++)
        ListTile(
          dense: true,
          visualDensity: VisualDensity.compact,
          title: SelectableText(
            '${r.headers[i].$1}: ${r.headers[i].$2}',
            style: const TextStyle(fontFamily: 'monospace', fontSize: 13),
          ),
          trailing: IconButton(
            key: ValueKey('copy-header-$i'),
            tooltip: 'Copy value',
            icon: const Icon(Icons.copy, size: 16),
            onPressed: () async {
              await Clipboard.setData(ClipboardData(text: r.headers[i].$2));
              if (!mounted) return;
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(content: Text('${r.headers[i].$1} copied')),
              );
            },
          ),
        ),
    ],
  );

  Widget _body(HttpResponseRecord r) {
    final isImage = isImageResponse(r);
    final showImage = isImage && _preview;
    final text = _pretty ? prettyBody(r) : r.bodyText;
    final matches = countMatches(text, _query);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8),
          child: Row(
            children: [
              SegmentedButton<String>(
                key: const Key('body-view'),
                showSelectedIcon: false,
                segments: [
                  const ButtonSegment(value: 'pretty', label: Text('Pretty')),
                  const ButtonSegment(value: 'raw', label: Text('Raw')),
                  if (isImage)
                    const ButtonSegment(
                      value: 'preview',
                      label: Text('Preview'),
                    ),
                ],
                selected: {
                  showImage ? 'preview' : (_pretty ? 'pretty' : 'raw'),
                },
                onSelectionChanged: (s) => setState(() {
                  _preview = s.first == 'preview';
                  if (!_preview) _pretty = s.first == 'pretty';
                }),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: TextField(
                  key: const Key('response-search'),
                  decoration: InputDecoration(
                    isDense: true,
                    hintText: 'Search',
                    prefixIcon: const Icon(Icons.search, size: 18),
                    suffixText: _query.isEmpty ? null : '$matches',
                  ),
                  onChanged: (v) => setState(() => _query = v),
                ),
              ),
              IconButton(
                key: const Key('copy-body'),
                tooltip: 'Copy body',
                icon: const Icon(Icons.copy, size: 18),
                onPressed: () async {
                  await Clipboard.setData(ClipboardData(text: text));
                  if (!mounted) return;
                  ScaffoldMessenger.of(
                    context,
                  ).showSnackBar(const SnackBar(content: Text('Body copied')));
                },
              ),
            ],
          ),
        ),
        Expanded(
          child: showImage
              ? Center(
                  child: Image.memory(
                    r.body,
                    key: const Key('response-image'),
                    errorBuilder: (_, _, _) =>
                        const Text('This image cannot be displayed'),
                  ),
                )
              : CodeView(
                  text: text,
                  fontSize: widget.codeFontSize,
                  json:
                      _pretty &&
                      (r
                              .header('content-type')
                              ?.toLowerCase()
                              .contains('json') ??
                          false),
                  query: _query,
                ),
        ),
      ],
    );
  }

  Widget _cookies(List<SetCookie> cookies) {
    if (cookies.isEmpty) {
      return const Center(child: Text('This response set no cookies'));
    }
    return ListView(
      key: const Key('response-cookies'),
      children: [
        for (final c in cookies)
          ListTile(
            dense: true,
            title: Text('${c.name} = ${c.value}'),
            subtitle: Text(
              c.attributes.entries
                  .map((e) => e.value.isEmpty ? e.key : '${e.key}=${e.value}')
                  .join('; '),
            ),
          ),
      ],
    );
  }

  Widget _scroll(String text, {Key? key}) => SingleChildScrollView(
    padding: const EdgeInsets.all(8),
    child: SelectableText(
      text,
      key: key,
      style: const TextStyle(fontFamily: 'monospace', fontSize: 13),
    ),
  );
}
