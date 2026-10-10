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
          return Column(
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
              Expanded(
                child: _Panes(
                  requestId: requestId,
                  state: state,
                  notifier: notifier,
                  compact: compact,
                ),
              ),
            ],
          );
        },
      ),
    );
  }
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

/// Request tabs stacked above the response.
class _Panes extends ConsumerWidget {
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

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return LayoutBuilder(
      builder: (context, c) {
        final request = _RequestTabs(
          requestId: requestId,
          item: state.item,
          notifier: notifier,
        );
        // Nothing to show yet: on a phone the request gets the whole screen.
        // The pane is collapsed rather than removed so the request tabs keep
        // their selection when the first response arrives.
        final collapsed =
            compact &&
            state.response == null &&
            state.error == null &&
            !state.sending;
        final response = _response(context, ref);
        final layout = ref.watch(splitLayoutProvider);
        // Side by side is cramped below tablet width; stack instead.
        final sideBySide =
            layout.horizontal && c.maxWidth >= LayoutClass.mediumBreakpoint;
        return Stack(
          children: [
            SplitView(
              axis: sideBySide ? Axis.horizontal : Axis.vertical,
              ratio: collapsed ? 1 : layout.ratio,
              onRatioChanged: (r) {
                if (collapsed) return;
                ref
                    .read(splitLayoutProvider.notifier)
                    .update(layout.copyWith(ratio: r));
              },
              first: request,
              second: collapsed ? const SizedBox.shrink() : response,
            ),
            // The toggle floats over the tab row, and a phone cannot split
            // sideways anyway.
            if (!compact)
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
                      .update(layout.copyWith(horizontal: !layout.horizontal)),
                ),
              ),
          ],
        );
      },
    );
  }

  Widget _response(BuildContext context, WidgetRef ref) {
    final port = ref.read(filePortProvider);
    final r = state.response;
    return ResponseView(
      state: state,
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
