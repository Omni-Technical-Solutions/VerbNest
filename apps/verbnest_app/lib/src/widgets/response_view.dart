import 'dart:convert';

import 'ui/still_controls.dart';

import 'package:material_ui/material_ui.dart';
import 'package:flutter/services.dart';
import 'package:verbnest_core/verbnest_core.dart'
    show
        BodyKind,
        ColumnType,
        ResultTable,
        TableReading,
        TableSource,
        bodyKindOf,
        filterBody,
        hexDump,
        looksTabular,
        readTable,
        readTableAsync,
        tableIsolateThreshold,
        tableMaxBytes;
import 'package:verbnest_http/verbnest_http.dart';

import '../state/cookies.dart';
import '../state/editor_state.dart';
import '../theme.dart';
import 'code_view.dart';
import 'result_table_view.dart';
import 'html_preview.dart';
import 'pdf_preview.dart';
import 'ui/adaptive_dialog.dart';
import 'ui/scroll_edge_fade.dart';
import 'ui/still_dropdown.dart';
import 'ui/still_tabs.dart';
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
    this.onSaveCsv,
    this.share = false,
    this.codeFontSize = 13,
  });

  final EditorState state;

  /// Saves or shares the response body; the button shows only when set.
  final VoidCallback? onSave;

  /// Saves or shares the table as CSV; the grid's menu item shows only when set.
  final Future<void> Function(String csv)? onSaveCsv;
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
  bool _wrap = false;

  /// Table view of the body (FR-RES-008) and its options.
  bool _table = false;
  String? _tableSource;
  bool _flatten = false;
  bool _headerRow = false;

  /// Phone only: the search and filter fields open from toolbar buttons so
  /// the toolbar is one row.
  bool _showSearch = false;
  bool _showFilter = false;
  String _query = '';
  String _filter = '';

  @override
  Widget build(BuildContext context) {
    final state = widget.state;
    // Sending, the error and the response replace each other at once; a
    // cross-fade on every send is motion the content does not need.
    final body = KeyedSubtree(
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
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SizedBox(
          height: 3,
          // A still bar, not a sliding one: nothing in the app animates.
          child: state.sending
              ? ColoredBox(
                  color: Theme.of(context).colorScheme.primary
                      .withValues(alpha: 0.6),
                )
              : null,
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
      animationDuration: Duration.zero,
      length: 5,
      // Measured from outside the column: inside it the height is unbounded.
      child: LayoutBuilder(
        builder: (context, c) => Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Capped at a third of the pane so large text scrolls the status
            // line instead of overflowing.
            ConstrainedBox(
              constraints: BoxConstraints(maxHeight: c.maxHeight / 3),
              child: SingleChildScrollView(child: _statusBar(context, r)),
            ),
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
      ),
    );
  }

  Widget _statusBar(BuildContext context, HttpResponseRecord r) {
    // Tighter on a phone, where every row counts.
    final phone =
        MediaQuery.sizeOf(context).width < LayoutClass.mediumBreakpoint;
    return Padding(
      padding: phone
          ? const EdgeInsets.symmetric(horizontal: 8)
          : const EdgeInsets.all(8),
      child: Wrap(
        spacing: phone ? 8 : 12,
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
              child: ConstrainedBox(
                // 48 dp on touch screens, tighter with a pointer.
                constraints: BoxConstraints(
                  minHeight: showsKeyboardHints(context) ? 0 : 48,
                ),
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 6,
                    vertical: 4,
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(Icons.timer_outlined, size: 16),
                      const SizedBox(width: 4),
                      Text(
                        '${r.timings.total.inMilliseconds} ms',
                        style: const TextStyle(fontFeatures: kTabularFigures),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
          // The protocol version is the first thing to go on a very narrow screen.
          if (MediaQuery.sizeOf(context).width >= 360)
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
    final label = widget.share ? context.l10n.rvShare : context.l10n.rvSave;
    final icon = Icon(
      widget.share ? Icons.ios_share : Icons.save_alt,
      size: 18,
    );
    // A phone's status line is one row: the button is icon only there.
    if (MediaQuery.sizeOf(context).width < LayoutClass.mediumBreakpoint) {
      return IconButton(
        key: const Key('response-save'),
        tooltip: label,
        icon: icon,
        onPressed: widget.onSave,
      );
    }
    return TextButton.icon(
      key: const Key('response-save'),
      icon: icon,
      label: Text(label),
      onPressed: widget.onSave,
    );
  }

  Widget _tabBar(
    BuildContext context,
    EditorState state,
    List<SetCookie> cookies,
  ) {
    // Secondary tabs: these sit inside the response panel, under the status.
    return ScrollEdgeFade(
      child: StillTabBar(
        key: const Key('response-tabs'),
        secondary: true,
        // Five tabs do not fit a phone; scroll them rather than cut the labels.
        isScrollable:
            MediaQuery.sizeOf(context).width < LayoutClass.mediumBreakpoint,
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
      ),
    );
  }

  void _showTiming(HttpResponseRecord r) {
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

  void _showTls(TlsInfo t) {
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

  _TableInfo? _tableInfoCache;
  String? _tableInfoKey;

  /// The body read as a table, or none. A small body is read at once (typing in
  /// the search box rebuilds this, so the result is kept until the text or an
  /// option changes). A large one is not read until the Table view is chosen,
  /// and then in another isolate, so the screen does not stall; until then the
  /// segment is offered on a cheap guess. Bodies over [tableMaxBytes] are not
  /// offered a table.
  _TableInfo _tableInfo(HttpResponseRecord r, String text, BodyKind kind) {
    final filtered = text != r.bodyText && kind == BodyKind.json;
    final ct = filtered ? 'application/json' : r.header('content-type');
    final large = text.length > tableIsolateThreshold;
    final key =
        '${text.hashCode}|${text.length}|$ct|$_tableSource|$_flatten|$_headerRow|${large && _table}';
    if (_tableInfoKey == key && _tableInfoCache != null) {
      return _tableInfoCache!;
    }
    _tableInfoKey = key;
    if (r.body.length > tableMaxBytes || text.isEmpty) {
      return _tableInfoCache = const _TableInfo();
    }
    if (!large) {
      return _tableInfoCache = _TableInfo.from(
        readTable(
          text,
          ct,
          source: _tableSource,
          flatten: _flatten,
          firstRowHeader: _headerRow,
        ),
        asked: false,
      );
    }
    if (!looksTabular(ct, text)) return _tableInfoCache = const _TableInfo();
    if (!_table) return _tableInfoCache = const _TableInfo(guess: true);
    readTableAsync(
      text,
      ct,
      source: _tableSource,
      flatten: _flatten,
      firstRowHeader: _headerRow,
    ).then((reading) {
      // The body or an option may have changed while it was being read.
      if (!mounted || _tableInfoKey != key) return;
      setState(() => _tableInfoCache = _TableInfo.from(reading, asked: true));
    });
    return _tableInfoCache = const _TableInfo(loading: true);
  }

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
    final phone =
        MediaQuery.sizeOf(context).width < LayoutClass.mediumBreakpoint;
    final filterable =
        kind != BodyKind.other && !_hex && preview == _Preview.none;
    final text = _hex
        ? hexDump(r.body)
        : filtering
        ? _applyFilter(r, kind)
        : _bodyText(r);
    // Whether the body can be a table does not depend on the view chosen, so
    // the Table segment stays available from Hex or Preview.
    final info = _tableInfo(r, filtering ? text : r.bodyText, kind);
    final showTable = _table && info.canTable;
    return LayoutBuilder(
      builder: (context, c) => Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // At normal sizes this is just its content. Large text caps it at
          // half the pane and it scrolls, so the body keeps some room.
          ConstrainedBox(
            constraints: BoxConstraints(maxHeight: c.maxHeight * 0.5),
            child: SingleChildScrollView(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  _bodyToolbar(
                    r,
                    text,
                    preview,
                    canFilter: filterable,
                    canTable: info.canTable,
                    showTable: showTable,
                  ),
                  // On a phone the filter opens from the toolbar, and stays
                  // open while it is doing something.
                  if (filterable &&
                      (!phone || _showFilter || _filter.isNotEmpty))
                    _filterField(kind, filtering),
                ],
              ),
            ),
          ),
          Expanded(child: _bodyContent(r, text, preview, info, showTable)),
        ],
      ),
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

  Widget _bodyToolbar(
    HttpResponseRecord r,
    String text,
    _Preview preview, {
    required bool canFilter,
    required bool canTable,
    required bool showTable,
  }) {
    final canPreview =
        isImageResponse(r) || isHtmlResponse(r) || isPdfResponse(r);
    // Built for the width this toolbar has: a phone's row has no room for a
    // fourth segment, so there the table is a menu item.
    Widget modesFor(bool phone) => SegmentedButton<String>(
      key: const Key('body-view'),
      showSelectedIcon: false,
      // Tighter on a very narrow phone so "Pretty" does not wrap.
      style: MediaQuery.sizeOf(context).width < 360
          ? ButtonStyle(
              // Changing the view is a switch, not a transition.
              animationDuration: Duration.zero,
              padding: const WidgetStatePropertyAll(
                EdgeInsets.symmetric(horizontal: 4),
              ),
              // From the theme's label style, so the font family is kept.
              textStyle: WidgetStatePropertyAll(
                Theme.of(context).textTheme.labelLarge?.copyWith(fontSize: 13),
              ),
              visualDensity: VisualDensity.compact,
            )
          : const ButtonStyle(animationDuration: Duration.zero),
      // On a phone the modes share the full line instead of scrolling.
      expandedInsets: phone ? EdgeInsets.zero : null,
      emptySelectionAllowed: true,
      segments: [
        ButtonSegment(value: 'pretty', label: Text(context.l10n.rvPretty)),
        ButtonSegment(value: 'raw', label: Text(context.l10n.rvRaw)),
        ButtonSegment(value: 'hex', label: Text(context.l10n.rvHex)),
        if (canPreview)
          ButtonSegment(value: 'preview', label: Text(context.l10n.rvPreview)),
        if (canTable && !phone)
          ButtonSegment(value: 'table', label: Text(context.l10n.rvTable)),
      ],
      selected: {
        if (preview != _Preview.none)
          'preview'
        else if (_hex)
          'hex'
        else if (showTable)
          ...(phone ? <String>[] : ['table'])
        else
          _pretty ? 'pretty' : 'raw',
      },
      onSelectionChanged: (s) => setState(() {
        if (s.isEmpty) return;
        _preview = s.first == 'preview';
        _hex = s.first == 'hex';
        _table = s.first == 'table';
        if (!_preview && !_hex && !_table) _pretty = s.first == 'pretty';
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
    Future<void> copyBody() async {
      lightHaptic(context);
      await Clipboard.setData(ClipboardData(text: text));
      if (!mounted) return;
      showToast(context, context.l10n.rvBodyCopied);
    }

    final copy = IconButton(
      key: const Key('copy-body'),
      tooltip: context.l10n.rvCopyBody,
      icon: const Icon(Icons.copy, size: 18),
      onPressed: copyBody,
    );
    void toggleTable() => setState(() {
      _table = !showTable;
      if (_table) {
        _hex = false;
        _preview = false;
      }
    });
    // Wrapping applies to text; the table has its own cell cutting.
    final showWrap = !_hex && preview == _Preview.none && !showTable;
    final wrap = IconButton(
      key: const Key('wrap-body'),
      tooltip: context.l10n.rvWrap,
      isSelected: _wrap,
      icon: const Icon(Icons.wrap_text, size: 18),
      onPressed: () => setState(() => _wrap = !_wrap),
    );
    // A phone's row has room for the modes, search and filter and one more
    // button: the rest of the actions live in its menu.
    final more = PopupMenuButton<String>(
      popUpAnimationStyle: AnimationStyle.noAnimation,
      key: const Key('body-more'),
      tooltip: MaterialLocalizations.of(context).showMenuTooltip,
      // The mode switch has no Table segment on a phone, so the menu button
      // shows that the table is on.
      icon: Icon(showTable ? Icons.table_chart : Icons.more_vert),
      onSelected: (v) {
        switch (v) {
          case 'table':
            toggleTable();
          case 'wrap':
            setState(() => _wrap = !_wrap);
          case 'copy':
            copyBody();
        }
      },
      itemBuilder: (context) => [
        if (canTable)
          CheckedPopupMenuItem(
            key: const Key('menu-table'),
            value: 'table',
            checked: showTable,
            child: Text(context.l10n.rvTable),
          ),
        if (showWrap)
          CheckedPopupMenuItem(
            key: const Key('menu-wrap'),
            value: 'wrap',
            checked: _wrap,
            child: Text(context.l10n.rvWrap),
          ),
        PopupMenuItem(
          key: const Key('menu-copy'),
          value: 'copy',
          child: Text(context.l10n.rvCopyBody),
        ),
      ],
    );
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8),
      child: LayoutBuilder(
        builder: (context, c) => c.maxWidth < LayoutClass.mediumBreakpoint
            ? Column(
                children: [
                  Row(
                    children: [
                      Expanded(child: modesFor(true)),
                      IconButton(
                        key: const Key('response-search-toggle'),
                        tooltip: context.l10n.rvSearch,
                        isSelected: _showSearch || _query.isNotEmpty,
                        icon: const Icon(Icons.search),
                        onPressed: () =>
                            setState(() => _showSearch = !_showSearch),
                      ),
                      if (canFilter)
                        IconButton(
                          key: const Key('response-filter-toggle'),
                          tooltip: context.l10n.rvFilter,
                          isSelected: _showFilter || _filter.isNotEmpty,
                          icon: const Icon(Icons.filter_alt_outlined),
                          onPressed: () =>
                              setState(() => _showFilter = !_showFilter),
                        ),
                      more,
                    ],
                  ),
                  if (_showSearch || _query.isNotEmpty) search,
                ],
              )
            : Row(
                children: [
                  modesFor(false),
                  const SizedBox(width: 8),
                  Expanded(child: search),
                  if (showWrap) wrap,
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

  Widget _bodyContent(
    HttpResponseRecord r,
    String text,
    _Preview preview,
    _TableInfo info,
    bool showTable,
  ) {
    if (showTable) return _tableBody(info);
    return _textContent(r, text, preview);
  }

  /// The grid, with a bar for the choices that shape it: which array the rows
  /// come from, flattening nested keys, and a header row. The search box above
  /// filters the rows.
  Widget _tableBody(_TableInfo info) {
    final table = info.table;
    if (table == null) {
      // Being read in another isolate, or not a table after all.
      return Center(
        child: info.loading
            ? Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(
                    Icons.hourglass_top,
                    key: Key('table-loading'),
                    size: 32,
                  ),
                  const SizedBox(height: 12),
                  Text(context.l10n.tableLoading),
                ],
              )
            : Text(
                context.l10n.tableNotTabular,
                key: const Key('table-not-tabular'),
              ),
      );
    }
    final l10n = context.l10n;
    final hasNested =
        _flatten || table.columns.any((c) => c.type == ColumnType.json);
    final sources = info.sources;
    // The grid shows these choices in its own bar, beside the copy menu.
    final options = sources.length > 1 || hasNested || info.matrix
        ? Wrap(
            spacing: 8,
            runSpacing: 4,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              if (sources.length > 1) ...[
                Text(l10n.tableRowsFrom),
                StillDropdown<String>(
                  key: const Key('table-source'),
                  value: sources.any((e) => e.path == _tableSource)
                      ? _tableSource
                      : table.label,
                  entries: [
                    for (final s in sources)
                      StillEntry(
                        value: s.path,
                        label: s.path == r'$'
                            ? l10n.tableWholeBody(s.count)
                            : '${s.path} (${s.count})',
                      ),
                  ],
                  onSelected: (v) => setState(() => _tableSource = v),
                ),
              ],
              if (hasNested)
                StillChip(
                  showCheckmark: true,
                  key: const Key('table-flatten'),
                  label: Text(l10n.tableFlatten),
                  selected: _flatten,
                  onSelected: (v) => setState(() => _flatten = v),
                ),
              if (info.matrix)
                StillChip(
                  showCheckmark: true,
                  key: const Key('table-header-row'),
                  label: Text(l10n.tableFirstRowHeader),
                  selected: _headerRow,
                  onSelected: (v) => setState(() => _headerRow = v),
                ),
            ],
          )
        : null;
    return ResultTableView(
      table: table,
      filter: _query,
      leading: options,
      onSaveCsv: widget.onSaveCsv,
    );
  }

  Widget _textContent(HttpResponseRecord r, String text, _Preview preview) =>
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
          wrap: _wrap,
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

/// A body read as a table, with the arrays it could be read from and whether it
/// is an array of arrays (which can take its first row as the header). A large
/// body is [guess]ed tabular, then [loading] while it is read in another
/// isolate; a body that turns out not to be a table is [failed].
class _TableInfo {
  const _TableInfo({
    this.table,
    this.sources = const [],
    this.matrix = false,
    this.loading = false,
    this.guess = false,
    this.failed = false,
  });

  /// [asked] is true when the person chose the Table view of a large body: a
  /// failed read is then reported. A small body that is not a table simply has
  /// no Table view.
  factory _TableInfo.from(TableReading r, {required bool asked}) =>
      r.table == null
      ? (asked ? const _TableInfo(failed: true) : const _TableInfo())
      : _TableInfo(table: r.table, sources: r.sources, matrix: r.matrix);

  final ResultTable? table;
  final List<TableSource> sources;
  final bool matrix;
  final bool loading;
  final bool guess;
  final bool failed;

  /// Whether the Table view is on offer.
  bool get canTable => table != null || loading || guess || failed;
}
