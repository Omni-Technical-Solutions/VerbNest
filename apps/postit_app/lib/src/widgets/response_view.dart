import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:postit_http/postit_http.dart';

import '../state/cookies.dart';
import '../state/editor_state.dart';

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

Color statusColor(int status) {
  if (status >= 500) return Colors.red.shade700;
  if (status >= 400) return Colors.orange.shade800;
  if (status >= 300) return Colors.blue.shade700;
  return Colors.green.shade700;
}

/// Status line plus Body / Cookies / Headers / Sent tabs (FR-RES-001..).
class ResponseView extends StatefulWidget {
  const ResponseView({super.key, required this.state});

  final EditorState state;

  @override
  State<ResponseView> createState() => _ResponseViewState();
}

class _ResponseViewState extends State<ResponseView> {
  bool _pretty = true;
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
                Text(formatBytes(r.body.length)),
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
                _scroll(
                  r.headers.map((h) => '${h.$1}: ${h.$2}').join('\n'),
                  key: const Key('response-headers'),
                ),
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

  Widget _body(HttpResponseRecord r) {
    final text = _pretty ? prettyBody(r) : r.bodyText;
    final matches = countMatches(text, _query);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8),
          child: Row(
            children: [
              SegmentedButton<bool>(
                key: const Key('body-view'),
                showSelectedIcon: false,
                segments: const [
                  ButtonSegment(value: true, label: Text('Pretty')),
                  ButtonSegment(value: false, label: Text('Raw')),
                ],
                selected: {_pretty},
                onSelectionChanged: (s) => setState(() => _pretty = s.first),
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
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(8),
            child: SelectableText.rich(
              _highlight(text, _query),
              key: const Key('response-body'),
              style: const TextStyle(fontFamily: 'monospace', fontSize: 13),
            ),
          ),
        ),
      ],
    );
  }

  TextSpan _highlight(String text, String query) {
    if (query.isEmpty) return TextSpan(text: text);
    final lower = text.toLowerCase();
    final q = query.toLowerCase();
    final spans = <TextSpan>[];
    var at = 0;
    for (var i = lower.indexOf(q); i != -1; i = lower.indexOf(q, at)) {
      if (i > at) spans.add(TextSpan(text: text.substring(at, i)));
      spans.add(
        TextSpan(
          text: text.substring(i, i + q.length),
          style: const TextStyle(
            backgroundColor: Color(0xFFFFE082),
            color: Colors.black,
          ),
        ),
      );
      at = i + q.length;
    }
    if (at < text.length) spans.add(TextSpan(text: text.substring(at)));
    return TextSpan(children: spans);
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
