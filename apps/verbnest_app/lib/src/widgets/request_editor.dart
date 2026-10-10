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
import 'ui/split_view.dart';
import 'ui/ui.dart';
import '../../l10n/l10n.dart';
import 'ui/toast.dart';

export 'request_editor/url_bar.dart' show httpMethods;

/// Editor for one request: URL bar, request tabs and the response.
class RequestEditor extends ConsumerWidget {
  const RequestEditor({super.key, required this.requestId});

  final String requestId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(editorProvider(requestId));
    final notifier = ref.read(editorProvider(requestId).notifier);
    final session = ref.read(sessionProvider);
    final envId = ref.watch(activeEnvProvider);

    return VariableContext(
      scopes: () => buildScopes(session, requestId: requestId, envId: envId),
      child: LayoutBuilder(
        builder: (context, c) {
          final compact = c.maxWidth < LayoutClass.mediumBreakpoint;
          // The page scrolls, so a short window (landscape, or a keyboard on
          // screen) never overflows: the panes get what is left, but at least
          // [_minPaneHeight], and the page scrolls past the rest.
          return CustomScrollView(
            keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
            slivers: [
              SliverToBoxAdapter(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    _Toolbar(
                      requestId: requestId,
                      compact: compact,
                      item: state.item,
                      notifier: notifier,
                    ),
                    UrlBar(state: state, notifier: notifier, compact: compact),
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
          );
        },
      ),
    );
  }

  /// The least height the request and response panes are given.
  static const _minPaneHeight = 240.0;
}

class _Toolbar extends StatelessWidget {
  const _Toolbar({
    required this.requestId,
    required this.compact,
    required this.item,
    required this.notifier,
  });

  final String requestId;
  final bool compact;
  final HttpRequestItem item;
  final EditorNotifier notifier;

  void _examples(BuildContext context) => showDialog<void>(
    context: context,
    builder: (_) => UncontrolledProviderScope(
      container: ProviderScope.containerOf(context),
      child: ExamplesDialog(requestId: requestId),
    ),
  );

  @override
  Widget build(BuildContext context) {
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
              IconButton(
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
  static const sideBySideWidth = 1100.0;

  @override
  ConsumerState<_Panes> createState() => _PanesState();
}

class _PanesState extends ConsumerState<_Panes> {
  /// Compact only: which pane is showing.
  bool _showResponse = false;

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
    final response = _response(context, ref);
    if (widget.compact) return _compactPanes(context, request, response);

    return LayoutBuilder(
      builder: (context, c) {
        final layout = ref.watch(splitLayoutProvider);
        final sideBySide =
            (layout.horizontal ?? c.maxWidth >= _Panes.sideBySideWidth) &&
            c.maxWidth >= LayoutClass.mediumBreakpoint;
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
            ),
            PositionedDirectional(
              end: 4,
              top: 4,
              child: IconButton(
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
            ? Padding(
                padding: const EdgeInsets.fromLTRB(
                  Space.md,
                  0,
                  Space.md,
                  Space.sm,
                ),
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

  Widget _response(BuildContext context, WidgetRef ref) {
    final port = ref.read(filePortProvider);
    final r = _state.response;
    return ResponseView(
      state: _state,
      codeFontSize: ref.watch(prefsProvider).editorFontSize,
      share: port.savesBySharing,
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
      length: 7,
      child: Column(
        children: [
          TabBar(
            isScrollable: true,
            tabAlignment: TabAlignment.start,
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

  List<Widget> _views() => [
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
  ];
}
