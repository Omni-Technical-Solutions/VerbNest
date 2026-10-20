import 'ui/still_controls.dart';

import 'package:material_ui/material_ui.dart';
import 'package:flutter/services.dart';
import 'package:verbnest_core/verbnest_core.dart'
    show BodyKind, ColumnType, bodyKindOf, hexDump;
import 'package:verbnest_http/verbnest_http.dart';

import '../state/cookies.dart';
import '../state/editor_state.dart';
import '../theme.dart';
import 'code_view.dart';
import 'result_table_view.dart';
import 'html_preview.dart';
import 'pdf_preview.dart';
import 'response_body_cache.dart';
import 'response_panels.dart';

export 'response_body_cache.dart' show prettyBody;

export 'response_panels.dart' show formatDuration, timingRows;
import 'ui/scroll_edge_fade.dart';
import 'ui/still_dropdown.dart';
import 'ui/still_tabs.dart';
import 'ui/ui.dart';
import '../../l10n/l10n.dart';
import '../layout_class.dart';
import 'ui/toast.dart';
import 'ui/still_tooltip.dart';

String formatBytes(int n) {
  if (n < 1024) return '$n B';
  if (n < 1024 * 1024) return '${(n / 1024).toStringAsFixed(1)} KB';
  return '${(n / 1024 / 1024).toStringAsFixed(1)} MB';
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
    this.maximized = false,
    this.onToggleMaximize,
    this.onWantsRoom,
  });

  final EditorState state;

  /// The response has the whole editor (the request pane is hidden); with
  /// [onToggleMaximize] set, a button in the status row switches it.
  final bool maximized;
  final VoidCallback? onToggleMaximize;

  /// Called, in the same frame, when a view needs more room than a pane
  /// usually has (the table), so the editor can give it the whole height.
  final VoidCallback? onWantsRoom;

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
  final _cache = ResponseBodyCache();
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
                  ResponseCookiesPanel(cookies),
                  ResponseHeadersPanel(r),
                  _scroll(
                    responseSentText(state),
                    key: const Key('response-sent'),
                  ),
                  ResponseTestsPanel(state),
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
          StillTooltip(
            message: context.l10n.rvTiming,
            child: InkWell(
              key: const Key('response-timing'),
              borderRadius: BorderRadius.circular(Radii.sm),
              onTap: () => showResponseTiming(context, r),
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
              onTap: () => showResponseTls(context, r.tls!),
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
          if (widget.onToggleMaximize != null)
            StillIconButton(
              key: const Key('maximize-response'),
              tooltip: widget.maximized
                  ? context.l10n.reRestorePanes
                  : context.l10n.reMaximizeResponse,
              icon: Icon(
                widget.maximized ? Icons.close_fullscreen : Icons.open_in_full,
                size: 18,
              ),
              onPressed: widget.onToggleMaximize,
            ),
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
      return StillIconButton(
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
          Tab(text: responseTestsLabel(context, state)),
        ],
      ),
    );
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
        ? _cache.filtered(r, kind, _filter)
        : _cache.text(r, pretty: _pretty);
    // Whether the body can be a table does not depend on the view chosen, so
    // the Table segment stays available from Hex or Preview.
    final info = _cache.table(
      r,
      filtering ? text : r.bodyText,
      kind,
      source: _tableSource,
      flatten: _flatten,
      headerRow: _headerRow,
      tableOn: _table,
      onReady: () {
        if (mounted) setState(() {});
      },
    );
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
                  // The table needs the height, so there it opens the same way.
                  if (filterable &&
                      ((!phone && !showTable) ||
                          _showFilter ||
                          _filter.isNotEmpty))
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
        if (_table) widget.onWantsRoom?.call();
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

    final copy = StillIconButton(
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
        widget.onWantsRoom?.call();
      }
    });
    // Wrapping applies to text; the table has its own cell cutting.
    final showWrap = !_hex && preview == _Preview.none && !showTable;
    final wrap = StillIconButton(
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
        // Large text needs the room a phone row saves.
        builder: (context, c) =>
            c.maxWidth <
                LayoutClass.mediumBreakpoint *
                    (MediaQuery.textScalerOf(context).scale(14) / 14).clamp(
                      1.0,
                      4.0,
                    )
            ? Column(
                children: [
                  Row(
                    children: [
                      Expanded(child: modesFor(true)),
                      StillIconButton(
                        key: const Key('response-search-toggle'),
                        tooltip: context.l10n.rvSearch,
                        isSelected: _showSearch || _query.isNotEmpty,
                        icon: const Icon(Icons.search),
                        onPressed: () =>
                            setState(() => _showSearch = !_showSearch),
                      ),
                      if (canFilter)
                        StillIconButton(
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
                  if (canFilter && showTable)
                    StillIconButton(
                      key: const Key('response-filter-toggle'),
                      tooltip: context.l10n.rvFilter,
                      isSelected: _showFilter || _filter.isNotEmpty,
                      icon: const Icon(Icons.filter_alt_outlined),
                      onPressed: () =>
                          setState(() => _showFilter = !_showFilter),
                    ),
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
        errorText: filtering ? _cache.filterError : null,
      ),
      onChanged: (v) => setState(() => _filter = v),
    ),
  );

  Widget _bodyContent(
    HttpResponseRecord r,
    String text,
    _Preview preview,
    TableInfo info,
    bool showTable,
  ) {
    if (showTable) return _tableBody(info);
    return _textContent(r, text, preview);
  }

  /// The grid, with a bar for the choices that shape it: which array the rows
  /// come from, flattening nested keys, and a header row. The search box above
  /// filters the rows.
  Widget _tableBody(TableInfo info) {
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

  Widget _scroll(String text, {Key? key}) => SingleChildScrollView(
    padding: const EdgeInsets.all(8),
    child: SelectableText(text, key: key, style: monoStyle(fontSize: 13)),
  );
}
