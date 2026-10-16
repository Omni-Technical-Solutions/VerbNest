import 'dart:typed_data';

import 'ui/still_tabs.dart';

import 'dart:convert';

import 'package:flutter/foundation.dart'
    show TargetPlatform, defaultTargetPlatform;
import 'package:material_ui/material_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:verbnest_core/verbnest_core.dart';

import '../state/editor_state.dart';
import '../state/file_port.dart';
import '../state/prefs.dart';
import '../state/session.dart';
import '../state/settings_state.dart';
import '../state/variables.dart';
import 'assertions_editor.dart';
import 'auth_editor.dart';
import 'env_selector.dart';
import 'request_editor/body_tab.dart';
import 'request_editor/headers_tab.dart';
import 'request_editor/params_tab.dart';
import 'request_editor/settings_tab.dart';
import 'request_editor/url_bar.dart';
import 'request_extras.dart';
import 'response_view.dart';
import 'scripts_editor.dart';
import 'synced_field.dart';
import '../layout_class.dart';
import '../theme.dart';
import 'ui/scroll_edge_fade.dart';
import 'ui/scroll_if_short.dart';
import 'ui/split_view.dart';
import 'ui/ui.dart';
import '../../l10n/l10n.dart';
import 'ui/toast.dart';
import 'ui/still_tooltip.dart';

export 'request_editor/url_bar.dart' show httpMethods;

/// Editor for one request: URL bar, request tabs and the response.
///
/// On a phone the URL bar is pinned and everything above it (the toolbar)
/// gets out of the way: it folds up while the keyboard is open and while you
/// scroll the content down, and comes back when you scroll up. Elsewhere the
/// toolbar stays put.
class RequestEditor extends ConsumerStatefulWidget {
  const RequestEditor({super.key, required this.requestId});

  final String requestId;

  @override
  ConsumerState<RequestEditor> createState() => _RequestEditorState();
}

class _RequestEditorState extends ConsumerState<RequestEditor> {
  /// Set while content is scrolled down and the toolbar is folded away.
  bool _hiddenByScroll = false;

  /// What the last drag asked for. The fold is applied when the scroll ends,
  /// so the pane is never resized under a finger.
  bool? _pendingHide;

  String get requestId => widget.requestId;

  static bool get _touchPlatform => switch (defaultTargetPlatform) {
    TargetPlatform.android ||
    TargetPlatform.iOS ||
    TargetPlatform.fuchsia => true,
    _ => false,
  };

  bool _onScroll(ScrollNotification n) {
    // Only the panes' own vertical scrolling counts, not the page's, and only
    // while a finger is dragging.
    if (n.depth == 0 || n.metrics.axis != Axis.vertical) return false;
    // Touch only. On a desktop (a narrow window, a trackpad) the content must
    // not resize under the pointer while it scrolls.
    if (!_touchPlatform) return false;
    if (n is ScrollEndNotification) {
      final hide = _pendingHide;
      _pendingHide = null;
      if (hide != null && hide != _hiddenByScroll) {
        setState(() => _hiddenByScroll = hide);
      }
      return false;
    }
    if (n is! ScrollUpdateNotification || n.dragDetails == null) return false;
    final delta = n.scrollDelta ?? 0;
    _pendingHide = n.metrics.pixels <= 8
        ? false // back at the top
        : (delta > 2 ? true : (delta < -2 ? false : _pendingHide));
    return false;
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(editorProvider(requestId));
    final notifier = ref.read(editorProvider(requestId).notifier);
    final session = ref.read(sessionProvider);
    final envId = ref.watch(activeEnvProvider);

    return VariableContext(
      scopes: () => buildScopes(session, requestId: requestId, envId: envId),
      child: LayoutBuilder(
        builder: (context, c) {
          final compact = c.maxWidth < LayoutClass.mediumBreakpoint;
          final narrow = c.maxWidth < 360;
          // A phone: narrow, or a landscape phone that is wide but short.
          final phone = compact || c.maxHeight < 480;
          // Read from the view: Scaffold removes the keyboard from the body's
          // MediaQuery. This builder re-runs when the keyboard resizes the body.
          final keyboardUp = View.of(context).viewInsets.bottom > 0;
          // A short window (a landscape phone) has no height for a toolbar row:
          // the environment and the menu move into the URL row.
          final short =
              MediaQuery.sizeOf(context).height < HeightClass.mediumBreakpoint;
          final hideToolbar =
              short || (phone && (keyboardUp || _hiddenByScroll));
          // The page scrolls, so a short window never overflows: the panes get
          // what is left, but at least [_minPaneHeight], and the page scrolls
          // past the rest. The URL bar is pinned so it is never scrolled away.
          return NotificationListener<ScrollNotification>(
            onNotification: _onScroll,
            child: CustomScrollView(
              keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
              slivers: [
                SliverToBoxAdapter(
                  // The toolbar folds away and returns at once (it used to size
                  // over 200 ms).
                  child: hideToolbar
                      ? const SizedBox(width: double.infinity)
                      : _Toolbar(
                          requestId: requestId,
                          compact: compact,
                          narrow: narrow,
                          item: state.item,
                          notifier: notifier,
                        ),
                ),
                SliverPersistentHeader(
                  pinned: true,
                  delegate: _PinnedHeader(
                    height: narrow ? _urlBarHeight - 8 : _urlBarHeight,
                    child: UrlBar(
                      state: state,
                      notifier: notifier,
                      compact: compact,
                      narrow: narrow,
                      trailing: short
                          ? Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                // A fixed width keeps the URL readable beside it.
                                EnvSelector(requestId: requestId, width: 140),
                                ToolbarMenu(
                                  requestId: requestId,
                                  item: state.item,
                                  notifier: notifier,
                                  onExamples: () =>
                                      showExamples(context, requestId),
                                ),
                              ],
                            )
                          : null,
                    ),
                  ),
                ),
                SliverToBoxAdapter(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      if (state.pendingUnresolved.isNotEmpty)
                        _PendingBanner(state: state, notifier: notifier),
                      if (state.pendingSecretHost != null)
                        _SecretHostBanner(state: state, notifier: notifier),
                      if (state.unresolved.isNotEmpty)
                        _Banner(
                          context.l10n.reUndefined(
                            state.unresolved.map((n) => '{{$n}}').join(', '),
                          ),
                        ),
                      for (final w in state.warnings) _Banner(w),
                    ],
                  ),
                ),
                SliverLayoutBuilder(
                  builder: (context, sc) {
                    final remaining =
                        sc.viewportMainAxisExtent - sc.precedingScrollExtent;
                    return SliverToBoxAdapter(
                      child: SizedBox(
                        height: remaining < _minPaneHeight
                            ? _minPaneHeight
                            : remaining,
                        child: _Panes(
                          requestId: requestId,
                          state: state,
                          notifier: notifier,
                          compact: compact,
                        ),
                      ),
                    );
                  },
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  /// Height of the pinned URL bar: its padding plus a 56 dp field.
  static const _urlBarHeight = 72.0;

  /// The least height the request and response panes are given.
  static const _minPaneHeight = 240.0;
}

/// Opens the saved examples of a request.
void showExamples(BuildContext context, String requestId) => showDialog<void>(
  animationStyle: AnimationStyle.noAnimation,
  context: context,
  builder: (_) => UncontrolledProviderScope(
    container: ProviderScope.containerOf(context),
    child: ExamplesDialog(requestId: requestId),
  ),
);

/// Keeps the URL bar at the top of the editor's scroll view. It has a solid
/// background so content scrolls under it cleanly.
class _PinnedHeader extends SliverPersistentHeaderDelegate {
  const _PinnedHeader({required this.height, required this.child});

  final double height;
  final Widget child;

  @override
  double get minExtent => height;

  @override
  double get maxExtent => height;

  @override
  Widget build(
    BuildContext context,
    double shrinkOffset,
    bool overlapsContent,
  ) => Material(
    color: Theme.of(context).colorScheme.surface,
    child: SizedBox(height: height, child: child),
  );

  @override
  bool shouldRebuild(_PinnedHeader old) =>
      old.height != height || old.child != child;
}

class _Toolbar extends ConsumerWidget {
  const _Toolbar({
    required this.requestId,
    required this.compact,
    required this.narrow,
    required this.item,
    required this.notifier,
  });

  final String requestId;
  final bool compact;

  /// Under 360 dp: favourite, examples and live sessions share one menu.
  final bool narrow;
  final HttpRequestItem item;
  final EditorNotifier notifier;

  void _examples(BuildContext context) => showExamples(context, requestId);

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (narrow) return _narrow(context, ref);
    return Align(
      alignment: AlignmentDirectional.centerEnd,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8),
        child: Wrap(
          alignment: WrapAlignment.end,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            FavouriteButton(requestId: requestId),
            if (compact)
              StillIconButton(
                key: const Key('examples'),
                tooltip: context.l10n.reExamples,
                icon: const Icon(Icons.bookmarks_outlined),
                onPressed: () => _examples(context),
              )
            else
              TextButton(
                key: const Key('examples'),
                onPressed: () => _examples(context),
                child: Text(context.l10n.reExamples),
              ),
            // On a phone the URL row has no room for this menu.
            if (compact) LiveMenu(item: item, notifier: notifier),
            EnvSelector(requestId: requestId),
          ],
        ),
      ),
    );
  }

  /// One row: the environment, and a menu with the rest.
  Widget _narrow(BuildContext context, WidgetRef ref) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8),
      child: Row(
        children: [
          Expanded(
            child: Align(
              alignment: AlignmentDirectional.centerEnd,
              child: EnvSelector(requestId: requestId),
            ),
          ),
          ToolbarMenu(
            requestId: requestId,
            item: item,
            notifier: notifier,
            onExamples: () => _examples(context),
          ),
        ],
      ),
    );
  }
}

/// The menu behind the toolbar's "more" button: favourite, examples and live
/// sessions. Used when the toolbar is one row (under 360 dp) and in the URL row
/// of a short window.
class ToolbarMenu extends ConsumerWidget {
  const ToolbarMenu({
    super.key,
    required this.requestId,
    required this.item,
    required this.notifier,
    required this.onExamples,
  });

  final String requestId;
  final HttpRequestItem item;
  final EditorNotifier notifier;
  final VoidCallback onExamples;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = context.l10n;
    final repo = ref.read(repositoryProvider);
    final fav = repo.isFavourite(requestId);
    return PopupMenuButton<String>(
      popUpAnimationStyle: AnimationStyle.noAnimation,
      key: const Key('toolbar-more'),
      tooltip: l.sbActions,
      icon: const Icon(Icons.more_vert),
      onSelected: (v) {
        switch (v) {
          case 'favourite':
            repo.setFavourite(requestId, !fav);
          case 'examples':
            onExamples();
          case 'ws':
            showLiveSession(context, ref, notifier, LiveKind.websocket);
          case 'sse':
            showLiveSession(context, ref, notifier, LiveKind.sse);
          case 'sub':
            showLiveSession(
              context,
              ref,
              notifier,
              LiveKind.graphqlSubscription,
            );
        }
      },
      itemBuilder: (_) => [
        PopupMenuItem(
          key: const Key('more-favourite'),
          value: 'favourite',
          child: Text(fav ? l.exFavRemove : l.exFavAdd),
        ),
        PopupMenuItem(
          key: const Key('more-examples'),
          value: 'examples',
          child: Text(l.reExamples),
        ),
        PopupMenuItem(value: 'ws', child: Text(l.reLiveWs)),
        PopupMenuItem(value: 'sse', child: Text(l.reLiveSse)),
        if (item.body is GraphqlBody)
          PopupMenuItem(value: 'sub', child: Text(l.reLiveSub)),
      ],
    );
  }
}

class _PendingBanner extends ConsumerWidget {
  const _PendingBanner({required this.state, required this.notifier});

  final EditorState state;
  final EditorNotifier notifier;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return InlineBanner(
      key: const Key('pending-banner'),
      tone: BannerTone.danger,
      child: Wrap(
        spacing: 8,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          Text(
            context.l10n.reNotDefined(
              state.pendingUnresolved.map((n) => '{{$n}}').join(', '),
            ),
          ),
          TextButton(
            key: const Key('send-anyway'),
            onPressed: () => notifier.send(force: true),
            child: Text(context.l10n.reSendAnyway),
          ),
          TextButton(
            key: const Key('dont-warn'),
            onPressed: () {
              ref.read(warnUnresolvedProvider.notifier).set(false);
              notifier.send(force: true);
            },
            child: Text(context.l10n.reDontWarn),
          ),
          TextButton(
            key: const Key('dismiss-pending'),
            onPressed: notifier.dismissPending,
            child: Text(context.l10n.reCancel),
          ),
        ],
      ),
    );
  }
}

class _SecretHostBanner extends StatelessWidget {
  const _SecretHostBanner({required this.state, required this.notifier});

  final EditorState state;
  final EditorNotifier notifier;

  @override
  Widget build(BuildContext context) {
    final pending = state.pendingSecretHost!;
    return InlineBanner(
      key: const Key('secret-host-banner'),
      tone: BannerTone.danger,
      child: Wrap(
        spacing: 8,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          Text(
            context.l10n.reSecretHostPrompt(
              pending.names.map((n) => '{{$n}}').join(', '),
              pending.host,
            ),
          ),
          TextButton(
            key: const Key('secret-host-allow'),
            onPressed: notifier.approveSecretHostAndSend,
            child: Text(context.l10n.reSecretHostAllow),
          ),
          TextButton(
            key: const Key('secret-host-cancel'),
            onPressed: notifier.dismissPending,
            child: Text(context.l10n.reCancel),
          ),
        ],
      ),
    );
  }
}

class _Banner extends StatelessWidget {
  const _Banner(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    return InlineBanner(
      tone: BannerTone.warning,
      child: Text(text, key: const Key('banner')),
    );
  }
}

/// Request and response panes.
///
/// Compact: one at a time behind a segmented switch, so each gets the whole
/// screen. Otherwise a split view; it sits side by side once the editor is
/// wide enough (the response becomes a supporting pane), unless the user chose
/// a direction.
class _Panes extends ConsumerStatefulWidget {
  const _Panes({
    required this.requestId,
    required this.state,
    required this.notifier,
    required this.compact,
  });

  final String requestId;
  final EditorState state;
  final EditorNotifier notifier;
  final bool compact;

  /// Editor width from which the response sits beside the request by default.
  static const sideBySideWidth = 820.0;

  @override
  ConsumerState<_Panes> createState() => _PanesState();
}

class _PanesState extends ConsumerState<_Panes> {
  /// Compact only: which pane is showing.
  bool _showResponse = false;

  /// Wide layouts: the response has the whole editor (the table asks for it).
  bool _maximized = false;

  /// Whether the last layout stacked the panes (only then does the table ask
  /// for the whole editor; side by side it already has the height).
  bool _stacked = false;

  @override
  void didUpdateWidget(_Panes old) {
    super.didUpdateWidget(old);
    // A send takes you to its result.
    if (!_resultOf(old.state) && _resultOf(widget.state)) _showResponse = true;
  }

  EditorState get _state => widget.state;

  static bool _resultOf(EditorState s) =>
      s.response != null || s.error != null || s.sending;

  bool get _hasResult => _resultOf(_state);

  @override
  Widget build(BuildContext context) {
    final request = _RequestTabs(
      requestId: widget.requestId,
      item: _state.item,
      notifier: widget.notifier,
    );
    final response = _response(context, ref, maximizable: !widget.compact);
    if (widget.compact) return _compactPanes(context, request, response);

    return LayoutBuilder(
      builder: (context, c) {
        final layout = ref.watch(splitLayoutProvider);
        // A short window (a landscape phone) never stacks the panes: there is
        // width to spare and no height, so they sit side by side.
        final short =
            MediaQuery.sizeOf(context).height < HeightClass.mediumBreakpoint;
        final sideBySide =
            c.maxWidth >= LayoutClass.mediumBreakpoint &&
            (short ||
                (layout.horizontal ?? c.maxWidth >= _Panes.sideBySideWidth));
        _stacked = !sideBySide;
        return Stack(
          children: [
            SplitView(
              axis: sideBySide ? Axis.horizontal : Axis.vertical,
              ratio: layout.ratio,
              onRatioChanged: (r) => ref
                  .read(splitLayoutProvider.notifier)
                  .update(layout.copyWith(ratio: r)),
              first: request,
              second: response,
              collapseFirst: _maximized && _hasResult,
            ),
            if (!short && !(_maximized && _hasResult))
              PositionedDirectional(
                end: 4,
                top: 4,
                child: StillIconButton(
                  key: const Key('split-orientation'),
                  visualDensity: VisualDensity.compact,
                  tooltip: sideBySide
                      ? context.l10n.reSplitStacked
                      : context.l10n.reSplitSideBySide,
                  icon: Icon(
                    sideBySide ? Icons.view_agenda_outlined : Icons.view_column,
                    size: 18,
                  ),
                  onPressed: () => ref
                      .read(splitLayoutProvider.notifier)
                      .update(layout.copyWith(horizontal: !sideBySide)),
                ),
              ),
          ],
        );
      },
    );
  }

  Widget _compactPanes(BuildContext context, Widget request, Widget response) {
    final showResponse = _hasResult && _showResponse;
    return Column(
      children: [
        // The slot always exists so the panes below keep their state.
        _hasResult
            // A swipe on the switch moves between the panes. It is limited to
            // the switch so it never competes with the horizontal scrolling
            // inside the panes.
            ? GestureDetector(
                key: const Key('pane-swipe'),
                behavior: HitTestBehavior.opaque,
                onHorizontalDragEnd: (d) {
                  final v = d.primaryVelocity ?? 0;
                  if (v.abs() < 200) return;
                  // Swiping against the reading direction goes forward.
                  final rtl = Directionality.of(context) == TextDirection.rtl;
                  final forward = rtl ? v > 0 : v < 0;
                  setState(() => _showResponse = forward);
                },
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(Space.md, 0, Space.md, 0),
                  child: SegmentedButton<bool>(
                    key: const Key('pane-switch'),
                    showSelectedIcon: false,
                    expandedInsets: EdgeInsets.zero,
                    segments: [
                      ButtonSegment(
                        value: false,
                        label: Text(context.l10n.histTabRequest),
                      ),
                      ButtonSegment(
                        value: true,
                        label: Text(context.l10n.histTabResponse),
                      ),
                    ],
                    selected: {showResponse},
                    onSelectionChanged: (s) =>
                        setState(() => _showResponse = s.first),
                  ),
                ),
              )
            : const SizedBox.shrink(),
        // Both stay mounted, so the selected request tab survives a send.
        Expanded(
          child: IndexedStack(
            index: showResponse ? 1 : 0,
            children: [request, response],
          ),
        ),
      ],
    );
  }

  Widget _response(
    BuildContext context,
    WidgetRef ref, {
    bool maximizable = false,
  }) {
    final port = ref.read(filePortProvider);
    final r = _state.response;
    return ResponseView(
      state: _state,
      codeFontSize: ref.watch(prefsProvider).editorFontSize,
      maximized: _maximized,
      onToggleMaximize: maximizable
          ? () => setState(() => _maximized = !_maximized)
          : null,
      // Synchronous, so the table and the room for it arrive in one frame.
      onWantsRoom: maximizable
          ? () {
              if (_stacked && !_maximized) setState(() => _maximized = true);
            }
          : null,
      share: port.savesBySharing,
      onSaveCsv: (csv) async {
        final ok = await port.save(
          'results.csv',
          Uint8List.fromList(utf8.encode(csv)),
          mime: 'text/csv',
        );
        if (ok && context.mounted) {
          showToast(context, context.l10n.reResponseSaved);
        }
      },
      onSave: r == null
          ? null
          : () async {
              final ok = await port.save(
                responseFileName(
                  r.headers,
                  r.finalUrl,
                  contentType: r.header('content-type'),
                ),
                r.body,
                mime: r.header('content-type')?.split(';').first,
              );
              if (ok && context.mounted) {
                showToast(context, context.l10n.reResponseSaved);
              }
            },
    );
  }
}

class _RequestTabs extends StatelessWidget {
  const _RequestTabs({
    required this.requestId,
    required this.item,
    required this.notifier,
  });

  final String requestId;
  final HttpRequestItem item;
  final EditorNotifier notifier;

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      animationDuration: Duration.zero,
      length: 7,
      child: Column(
        children: [
          ScrollEdgeFade(
            child: StillTabBar(
              isScrollable: true,
              tabs: [
                _tab(context.l10n.reTabParams, _active(item.params)),
                _tab(context.l10n.reTabHeaders, _active(item.headers)),
                Tab(text: context.l10n.reTabAuth),
                Tab(text: context.l10n.reTabBody),
                Tab(text: context.l10n.reTabScripts),
                _tab(context.l10n.reTabAssertions, item.assertions.length),
                Tab(text: context.l10n.reTabSettings),
              ],
            ),
          ),
          Expanded(child: TabBarView(children: _views())),
        ],
      ),
    );
  }

  static int _active(List<KeyValue> rows) =>
      rows.where((r) => r.enabled && r.key.isNotEmpty).length;

  static Widget _tab(String label, int count) => Tab(
    child: Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(label),
        if (count > 0) ...[const SizedBox(width: 6), CountBadge(count)],
      ],
    ),
  );

  // Each tab scrolls when it is given less room than a form needs (large
  // text, a landscape phone, the keyboard) instead of overflowing.
  List<Widget> _views() => [
    for (final v in [
      ParamsTab(item: item, notifier: notifier),
      HeadersTab(item: item, notifier: notifier, requestId: requestId),
      AuthEditor(
        auth: item.auth,
        onChanged: (a) => notifier.edit((i) => i.copyWith(auth: a)),
      ),
      BodyTab(item: item, notifier: notifier),
      Consumer(
        builder: (context, ref, _) => ScriptsEditor(
          scripts: item.scripts,
          fontSize: ref.watch(prefsProvider).editorFontSize,
          onChanged: (s) => notifier.edit((i) => i.copyWith(scripts: s)),
        ),
      ),
      AssertionsEditor(
        assertions: item.assertions,
        onChanged: (a) => notifier.edit((i) => i.copyWith(assertions: a)),
      ),
      SettingsTab(item: item, notifier: notifier),
    ])
      // Headers stacks an expandable group over the table: it needs more.
      ScrollIfShort(minHeight: v is HeadersTab ? 420 : 280, child: v),
  ];
}
