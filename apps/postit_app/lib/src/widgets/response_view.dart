import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:postit_http/postit_http.dart';

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

/// Status line plus Body / Headers / Sent tabs (FR-RES-001..).
class ResponseView extends StatelessWidget {
  const ResponseView({super.key, required this.state});

  final EditorState state;

  @override
  Widget build(BuildContext context) {
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
    return DefaultTabController(
      length: 3,
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
          const TabBar(
            tabs: [
              Tab(text: 'Body'),
              Tab(text: 'Headers'),
              Tab(text: 'Sent'),
            ],
          ),
          Expanded(
            child: TabBarView(
              children: [
                _scroll(prettyBody(r), key: const Key('response-body')),
                _scroll(
                  r.headers.map((h) => '${h.$1}: ${h.$2}').join('\n'),
                  key: const Key('response-headers'),
                ),
                _scroll(
                  state.maskedSentHead ?? '',
                  key: const Key('response-sent'),
                ),
              ],
            ),
          ),
        ],
      ),
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
