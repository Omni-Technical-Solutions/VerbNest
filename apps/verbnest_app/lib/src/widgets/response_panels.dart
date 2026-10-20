import 'package:flutter/services.dart';
import 'package:material_ui/material_ui.dart';
import 'package:verbnest_http/verbnest_http.dart';

import '../../l10n/l10n.dart';
import '../state/cookies.dart';
import '../state/editor_state.dart';
import '../theme.dart';
import 'ui/adaptive_dialog.dart';
import 'ui/still_tooltip.dart';

// The panels and dialogs of the response view that need no state of their own:
// tests, headers, cookies, the sent request, and the timing and TLS details.

/// The phases of one exchange in order. Phases that did not happen (plain
/// HTTP has no TLS) are left out. "Other" is time outside the measured phases,
/// such as writing the request.
List<(String, Duration)> timingRows(Timings t) {
  final measured = t.dns + t.connect + t.tls + t.ttfb + t.download;
  final other = t.total - measured;
  return [
    ('DNS lookup', t.dns),
    ('TCP connect', t.connect),
    if (t.tls > Duration.zero) ('TLS handshake', t.tls),
    ('Waiting (TTFB)', t.ttfb),
    ('Download', t.download),
    if (other > const Duration(milliseconds: 1)) ('Other', other),
  ];
}

String formatDuration(Duration d) => d.inMicroseconds < 1000
    ? '${d.inMicroseconds} µs'
    : d.inMilliseconds < 1000
    ? '${(d.inMicroseconds / 1000).toStringAsFixed(1)} ms'
    : '${(d.inMilliseconds / 1000).toStringAsFixed(2)} s';

/// The text of the request as it was sent, with secrets masked.
String responseSentText(EditorState s) {
  final head = s.maskedSentHead ?? '';
  final body = s.maskedSentBody ?? '';
  return body.isEmpty ? head : '${head.trimRight()}\n\n$body';
}

/// The label of the Tests tab: its name, or the pass count when there are tests.
String responseTestsLabel(BuildContext context, EditorState s) {
  if (s.tests.isEmpty && s.scriptError == null) {
    return context.l10n.rvTabTests;
  }
  final passed = s.tests.where((t) => t.passed).length;
  final counted = s.tests.where((t) => !t.status.startsWith('skip')).length;
  return context.l10n.rvTabTestsN(passed, counted);
}

/// Assertion and script results, and the script console.
class ResponseTestsPanel extends StatelessWidget {
  const ResponseTestsPanel(this.state, {super.key});

  final EditorState state;

  @override
  Widget build(BuildContext context) {
    final s = state;
    if (s.tests.isEmpty && s.scriptError == null && s.scriptLogs.isEmpty) {
      return Center(child: Text(context.l10n.rvNoTests));
    }
    final scheme = Theme.of(context).colorScheme;
    return ListView(
      key: const Key('response-tests'),
      padding: const EdgeInsets.all(8),
      children: [
        if (s.scriptError != null)
          ListTile(
            key: const Key('script-error'),
            leading: Icon(Icons.error_outline, color: scheme.error),
            title: Text(
              context.l10n.rvScriptError,
              style: TextStyle(color: scheme.error),
            ),
            subtitle: SelectableText(s.scriptError!),
          ),
        for (final t in s.tests)
          ListTile(
            dense: true,
            key: Key('test-${t.name}'),
            leading: Icon(
              switch (t.status) {
                'pass' => Icons.check_circle,
                'skip' => Icons.remove_circle_outline,
                _ => Icons.cancel,
              },
              color: switch (t.status) {
                'pass' => AppColors.of(context).success,
                'skip' => scheme.outline,
                _ => scheme.error,
              },
            ),
            title: Text(t.name),
            subtitle: t.message == null ? null : SelectableText(t.message!),
          ),
        if (s.scriptLogs.isNotEmpty) ...[
          const Divider(),
          Text(
            context.l10n.rvConsole,
            style: Theme.of(context).textTheme.titleSmall,
          ),
          for (final l in s.scriptLogs)
            SelectableText(
              '${l.level == 'log' ? '' : '${l.level}: '}${l.text}',
              style: monoStyle(fontSize: 12),
            ),
        ],
      ],
    );
  }
}

/// The response headers, each with a button that copies its value.
class ResponseHeadersPanel extends StatelessWidget {
  const ResponseHeadersPanel(this.response, {super.key});

  final HttpResponseRecord response;

  @override
  Widget build(BuildContext context) {
    final r = response;
    return ListView(
      key: const Key('response-headers'),
      children: [
        for (var i = 0; i < r.headers.length; i++)
          ListTile(
            dense: true,
            visualDensity: VisualDensity.compact,
            title: SelectableText(
              '${r.headers[i].$1}: ${r.headers[i].$2}',
              style: monoStyle(fontSize: 13),
            ),
            trailing: StillIconButton(
              key: ValueKey('copy-header-$i'),
              tooltip: context.l10n.rvCopyValue,
              icon: const Icon(Icons.copy, size: 16),
              onPressed: () async {
                await Clipboard.setData(ClipboardData(text: r.headers[i].$2));
                if (!context.mounted) return;
                ScaffoldMessenger.of(context).showSnackBar(
                  snackBarAnimationStyle: AnimationStyle.noAnimation,
                  SnackBar(
                    content: Text(context.l10n.rvHeaderCopied(r.headers[i].$1)),
                  ),
                );
              },
            ),
          ),
      ],
    );
  }
}

/// The cookies the response set.
class ResponseCookiesPanel extends StatelessWidget {
  const ResponseCookiesPanel(this.cookies, {super.key});

  final List<SetCookie> cookies;

  @override
  Widget build(BuildContext context) {
    if (cookies.isEmpty) {
      return Center(child: Text(context.l10n.rvNoCookies));
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
}

String _timingLabel(BuildContext context, String id) {
  final l = context.l10n;
  return switch (id) {
    'DNS lookup' => l.rvDns,
    'TCP connect' => l.rvTcp,
    'TLS handshake' => l.rvTlsHandshake,
    'Waiting (TTFB)' => l.rvTtfb,
    'Download' => l.rvDownload,
    'Other' => l.rvOther,
    _ => id,
  };
}

/// The timing breakdown of [r] in a dialog.
void showResponseTiming(BuildContext context, HttpResponseRecord r) {
  final rows = timingRows(r.timings);
  final total = r.timings.total.inMicroseconds;
  showDetail(
    context,
    title: context.l10n.rvTiming,
    closeLabel: context.l10n.rvClose,
    content: Column(
      key: const Key('timing-rows'),
      mainAxisSize: MainAxisSize.min,
      children: [
        for (final (label, d) in rows)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 4),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(child: Text(_timingLabel(context, label))),
                    Text(formatDuration(d)),
                  ],
                ),
                LinearProgressIndicator(
                  value: total == 0 ? 0 : d.inMicroseconds / total,
                ),
              ],
            ),
          ),
        const Divider(),
        Row(
          children: [
            Expanded(child: Text(context.l10n.rvTotal)),
            Text(formatDuration(r.timings.total)),
          ],
        ),
      ],
    ),
  );
}

/// The TLS certificate and protocol facts of a connection in a dialog.
void showResponseTls(BuildContext context, TlsInfo t) {
  String d(DateTime x) => x.toUtc().toIso8601String().substring(0, 10);
  showDetail(
    context,
    title: context.l10n.rvTlsTitle,
    closeLabel: context.l10n.rvClose,
    content: SelectableText(
      [
        context.l10n.rvTlsSubject(t.subject),
        context.l10n.rvTlsIssuer(t.issuer),
        context.l10n.rvTlsValid(d(t.validFrom), d(t.validTo)),
        if (t.protocol != null) context.l10n.rvTlsProtocol(t.protocol!),
        context.l10n.rvTlsClientCert(
          t.clientCertificateSent ? context.l10n.rvYes : context.l10n.rvNo,
        ),
      ].join('\n'),
    ),
  );
}
