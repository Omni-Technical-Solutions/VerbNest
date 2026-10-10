import 'dart:convert';

import 'package:material_ui/material_ui.dart';
import 'package:flutter/services.dart';
import 'package:verbnest_core/verbnest_core.dart'
    show BodyKind, bodyKindOf, filterBody, hexDump;
import 'package:verbnest_http/verbnest_http.dart';

import '../state/cookies.dart';
import '../state/editor_state.dart';
import '../theme.dart';
import 'code_view.dart';
import 'html_preview.dart';
import 'pdf_preview.dart';
import 'ui/ui.dart';
import '../../l10n/l10n.dart';
import '../layout_class.dart';
import 'ui/toast.dart';

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

bool isHtmlResponse(HttpResponseRecord r) =>
    (r.header('content-type') ?? '').toLowerCase().contains('text/html');

bool isPdfResponse(HttpResponseRecord r) =>
    (r.header('content-type') ?? '').toLowerCase().contains('application/pdf');

bool isImageResponse(HttpResponseRecord r) {
  final t = (r.header('content-type') ?? '').toLowerCase();
  return t.startsWith('image/') && !t.contains('svg');
}

/// Decoded size, plus the size on the wire when compression changed it.
String sizeLabel(HttpResponseRecord r, {String onWire = 'on the wire'}) =>
    r.wireBodySize == r.body.length
    ? formatBytes(r.body.length)
    : '${formatBytes(r.body.length)} (${formatBytes(r.wireBodySize)} $onWire)';

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

Color statusColor(BuildContext context, int status) =>
    AppColors.of(context).status(status);

/// Status line plus Body / Cookies / Headers / Sent tabs (FR-RES-001..).
class ResponseView extends StatefulWidget {
  const ResponseView({
    super.key,
    required this.state,
    this.onSave,
    this.share = false,
    this.codeFontSize = 13,
  });

  final EditorState state;

  /// Saves or shares the response body; the button shows only when set.
  final VoidCallback? onSave;
  final bool share;
  final double codeFontSize;

  @override
  State<ResponseView> createState() => _ResponseViewState();
}

enum _Preview { none, image, html, pdf }

class _ResponseViewState extends State<ResponseView> {
  bool _pretty = true;
  bool _preview = false;
  bool _hex = false;
  String _query = '';
  String _filter = '';

  @override
  Widget build(BuildContext context) {
    final state = widget.state;
    final body = AnimatedSwitcher(
      duration: Motion.of(context, Motion.base),
      switchInCurve: Motion.curve,
      child: KeyedSubtree(
        key: ValueKey(
          state.sending
              ? 'sending'
              : state.error != null
              ? 'error'
              : state.response == null
              ? 'empty'
              : 'response',
        ),
        child: _content(context, state),
      ),
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SizedBox(
          height: 3,
          child: state.sending ? const LinearProgressIndicator() : null,
        ),
        Expanded(child: body),
      ],
    );
  }

  Widget _content(BuildContext context, EditorState state) {
    if (state.sending) {
      return const Skeleton();
    }
    if (state.error != null) {
      return EmptyState(
        icon: Icons.error_outline,
        title: state.error!,
        titleKey: const Key('response-error'),
        titleColor: Theme.of(context).colorScheme.error,
      );
    }
    final r = state.response;
    if (r == null) {
      return EmptyState(
        icon: Icons.bolt_outlined,
        title: context.l10n.rvEmpty,
        hint: showsKeyboardHints(context) ? 'Ctrl/Cmd + Enter' : null,
      );
    }
    final cookies = [
      for (final (k, v) in r.headers)
        if (k.toLowerCase() == 'set-cookie') ?parseSetCookie(v),
    ];
    return DefaultTabController(
      length: 5,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _statusBar(context, r),
          _tabBar(context, state, cookies),
          Expanded(
            child: TabBarView(
              children: [
                _body(r),
                _cookies(cookies),
                _headers(r),
                _scroll(_sentText(state), key: const Key('response-sent')),
                _tests(state),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _statusBar(BuildContext context, HttpResponseRecord r) {
    return Padding(
      padding: const EdgeInsets.all(8),
      child: Wrap(
        spacing: 12,
        runSpacing: 4,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          StatusPill(
            r.status,
            '${r.status} ${r.reason}',
            key: const Key('response-status'),
          ),
          Tooltip(
            message: context.l10n.rvTiming,
            child: InkWell(
              key: const Key('response-timing'),
              borderRadius: BorderRadius.circular(Radii.sm),
              onTap: () => _showTiming(r),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.timer_outlined, size: 16),
                    const SizedBox(width: 4),
                    Text('${r.timings.total.inMilliseconds} ms'),
                  ],
                ),
              ),
            ),
          ),
          Text(
            context.l10n.rvHttpVersion(r.httpVersion),
            key: const Key('response-http'),
          ),
          Text(sizeLabel(r, onWire: context.l10n.rvOnWire)),
          if (r.tls != null)
            InkWell(
              key: const Key('response-tls'),
              onTap: () => _showTls(r.tls!),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.lock_outline, size: 16),
                  const SizedBox(width: 4),
                  Text(context.l10n.rvTls),
                ],
              ),
            ),
          if (widget.onSave != null) _saveButton(context),
        ],
      ),
    );
  }

  Widget _saveButton(BuildContext context) {
    return TextButton.icon(
      key: const Key('response-save'),
      icon: Icon(widget.share ? Icons.ios_share : Icons.save_alt, size: 18),
      label: Text(widget.share ? context.l10n.rvShare : context.l10n.rvSave),
      onPressed: widget.onSave,
    );
  }

  Widget _tabBar(
    BuildContext context,
    EditorState state,
    List<SetCookie> cookies,
  ) {
    return TabBar(
      // Five tabs do not fit a phone; scroll them rather than cut the labels.
      isScrollable:
          MediaQuery.sizeOf(context).width < LayoutClass.mediumBreakpoint,
      tabAlignment:
          MediaQuery.sizeOf(context).width < LayoutClass.mediumBreakpoint
          ? TabAlignment.start
          : null,
      tabs: [
        Tab(text: context.l10n.rvTabBody),
        Tab(
          text: cookies.isEmpty
              ? context.l10n.rvTabCookies
              : context.l10n.rvTabCookiesN(cookies.length),
        ),
        Tab(text: context.l10n.rvTabHeaders),
        Tab(text: context.l10n.rvTabSent),
        Tab(text: _testsLabel(context, state)),
      ],
    );
  }

  void _showTiming(HttpResponseRecord r) {
    final rows = timingRows(r.timings);
    final total = r.timings.total.inMicroseconds;
    showDialog<void>(
      context: context,
      builder: (_) => AlertDialog(
        title: Text(context.l10n.rvTiming),
        content: SizedBox(
          width: 360,
          child: Column(
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
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text(context.l10n.rvClose),
          ),
        ],
      ),
    );
  }

  void _showTls(TlsInfo t) {
    String d(DateTime x) => x.toUtc().toIso8601String().substring(0, 10);
    showDialog<void>(
      context: context,
      builder: (_) => AlertDialog(
        title: Text(context.l10n.rvTlsTitle),
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
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text(context.l10n.rvClose),
          ),
        ],
      ),
    );
  }

  static String _timingLabel(BuildContext context, String id) {
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

  static String _testsLabel(BuildContext context, EditorState s) {
    if (s.tests.isEmpty && s.scriptError == null) {
      return context.l10n.rvTabTests;
    }
    final passed = s.tests.where((t) => t.passed).length;
    final counted = s.tests.where((t) => !t.status.startsWith('skip')).length;
    return context.l10n.rvTabTestsN(passed, counted);
  }

  Widget _tests(EditorState s) {
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
            style: monoStyle(fontSize: 13),
          ),
          trailing: IconButton(
            key: ValueKey('copy-header-$i'),
            tooltip: context.l10n.rvCopyValue,
            icon: const Icon(Icons.copy, size: 16),
            onPressed: () async {
              await Clipboard.setData(ClipboardData(text: r.headers[i].$2));
              if (!mounted) return;
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: Text(context.l10n.rvHeaderCopied(r.headers[i].$1)),
                ),
              );
            },
          ),
        ),
    ],
  );

  HttpResponseRecord? _textFor;
  bool? _textPretty;
  String _text = '';

  /// Pretty-printing a large JSON body is slow, so keep the result until the
  /// response or the toggle changes (typing in the search box rebuilds this).
  String _bodyText(HttpResponseRecord r) {
    if (!identical(_textFor, r) || _textPretty != _pretty) {
      _textFor = r;
      _textPretty = _pretty;
      _text = _pretty ? prettyBody(r) : r.bodyText;
    }
    return _text;
  }

  HttpResponseRecord? _filteredFor;
  String? _filteredBy;
  String _filtered = '';
  String? _filterError;

  /// JSONPath/XPath over a large body is slow, so keep the result until the
  /// response or the expression changes.
  String _applyFilter(HttpResponseRecord r, BodyKind kind) {
    if (!identical(_filteredFor, r) || _filteredBy != _filter) {
      _filteredFor = r;
      _filteredBy = _filter;
      try {
        _filtered = filterBody(r.bodyText, kind, _filter);
        _filterError = null;
      } on FormatException catch (e) {
        _filtered = '';
        _filterError = e.message;
      }
    }
    return _filtered;
  }

  Widget _body(HttpResponseRecord r) {
    final kind = bodyKindOf(r.header('content-type'));
    final preview = _previewOf(r);
    final filtering =
        !_hex && kind != BodyKind.other && _filter.trim().isNotEmpty;
    final text = _hex
        ? hexDump(r.body)
        : filtering
        ? _applyFilter(r, kind)
        : _bodyText(r);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _bodyToolbar(r, text, preview),
        if (kind != BodyKind.other && !_hex && preview == _Preview.none)
          _filterField(kind, filtering),
        Expanded(child: _bodyContent(r, text, preview)),
      ],
    );
  }

  /// Which preview, if any, the toggle currently shows for [r].
  _Preview _previewOf(HttpResponseRecord r) {
    if (!_preview) return _Preview.none;
    if (isImageResponse(r)) return _Preview.image;
    if (isHtmlResponse(r)) return _Preview.html;
    if (isPdfResponse(r)) return _Preview.pdf;
    return _Preview.none;
  }

  Widget _bodyToolbar(HttpResponseRecord r, String text, _Preview preview) {
    final canPreview =
        isImageResponse(r) || isHtmlResponse(r) || isPdfResponse(r);
    final modes = SegmentedButton<String>(
      key: const Key('body-view'),
      showSelectedIcon: false,
      // On a phone the modes share the full line instead of scrolling.
      expandedInsets:
          MediaQuery.sizeOf(context).width < LayoutClass.mediumBreakpoint
          ? EdgeInsets.zero
          : null,
      segments: [
        ButtonSegment(value: 'pretty', label: Text(context.l10n.rvPretty)),
        ButtonSegment(value: 'raw', label: Text(context.l10n.rvRaw)),
        ButtonSegment(value: 'hex', label: Text(context.l10n.rvHex)),
        if (canPreview)
          ButtonSegment(value: 'preview', label: Text(context.l10n.rvPreview)),
      ],
      selected: {
        preview != _Preview.none
            ? 'preview'
            : _hex
            ? 'hex'
            : (_pretty ? 'pretty' : 'raw'),
      },
      onSelectionChanged: (s) => setState(() {
        _preview = s.first == 'preview';
        _hex = s.first == 'hex';
        if (!_preview && !_hex) _pretty = s.first == 'pretty';
      }),
    );
    final search = TextField(
      key: const Key('response-search'),
      decoration: InputDecoration(
        isDense: true,
        hintText: context.l10n.rvSearch,
        prefixIcon: const Icon(Icons.search, size: 18),
        suffixText: _query.isEmpty ? null : '${countMatches(text, _query)}',
      ),
      onChanged: (v) => setState(() => _query = v),
    );
    final copy = IconButton(
      key: const Key('copy-body'),
      tooltip: context.l10n.rvCopyBody,
      icon: const Icon(Icons.copy, size: 18),
      onPressed: () async {
        await Clipboard.setData(ClipboardData(text: text));
        if (!mounted) return;
        showToast(context, context.l10n.rvBodyCopied);
      },
    );
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8),
      child: LayoutBuilder(
        builder: (context, c) => c.maxWidth < LayoutClass.mediumBreakpoint
            // A phone has no room for the modes, search and copy side by side.
            ? Column(
                children: [
                  modes,
                  Row(
                    children: [
                      Expanded(child: search),
                      copy,
                    ],
                  ),
                ],
              )
            : Row(
                children: [
                  modes,
                  const SizedBox(width: 8),
                  Expanded(child: search),
                  copy,
                ],
              ),
      ),
    );
  }

  Widget _filterField(BodyKind kind, bool filtering) => Padding(
    padding: const EdgeInsets.fromLTRB(8, 4, 8, 0),
    child: TextField(
      key: const Key('response-filter'),
      decoration: InputDecoration(
        isDense: true,
        hintText: kind == BodyKind.json
            ? context.l10n.rvFilterJson
            : context.l10n.rvFilterXml,
        prefixIcon: const Icon(Icons.filter_alt_outlined, size: 18),
        errorText: filtering ? _filterError : null,
      ),
      onChanged: (v) => setState(() => _filter = v),
    ),
  );

  Widget _bodyContent(HttpResponseRecord r, String text, _Preview preview) =>
      switch (preview) {
        _Preview.pdf => PdfPreview(bytes: r.body),
        _Preview.html => HtmlPreview(html: r.bodyText, size: r.body.length),
        _Preview.image => Center(
          child: Image.memory(
            r.body,
            key: const Key('response-image'),
            errorBuilder: (_, _, _) => Text(context.l10n.rvImageError),
          ),
        ),
        _Preview.none => CodeView(
          text: text,
          fontSize: widget.codeFontSize,
          json:
              _pretty &&
              !_hex &&
              (r.header('content-type')?.toLowerCase().contains('json') ??
                  false),
          query: _query,
        ),
      };

  Widget _cookies(List<SetCookie> cookies) {
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

  Widget _scroll(String text, {Key? key}) => SingleChildScrollView(
    padding: const EdgeInsets.all(8),
    child: SelectableText(text, key: key, style: monoStyle(fontSize: 13)),
  );
}
