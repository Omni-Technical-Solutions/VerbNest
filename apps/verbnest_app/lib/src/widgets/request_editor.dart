import 'package:flutter/material.dart';
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
import '../../l10n/l10n.dart';

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
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _Toolbar(requestId: requestId),
          UrlBar(state: state, notifier: notifier),
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
            ),
          ),
        ],
      ),
    );
  }
}

class _Toolbar extends StatelessWidget {
  const _Toolbar({required this.requestId});

  final String requestId;

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: AlignmentDirectional.centerEnd,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            FavouriteButton(requestId: requestId),
            TextButton(
              key: const Key('examples'),
              onPressed: () => showDialog<void>(
                context: context,
                builder: (_) => UncontrolledProviderScope(
                  container: ProviderScope.containerOf(context),
                  child: ExamplesDialog(requestId: requestId),
                ),
              ),
              child: Text(context.l10n.reExamples),
            ),
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
    return Container(
      key: const Key('pending-banner'),
      color: Theme.of(context).colorScheme.errorContainer,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
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
    return Container(
      key: const Key('secret-host-banner'),
      color: Theme.of(context).colorScheme.errorContainer,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
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
    return Container(
      color: Theme.of(context).colorScheme.tertiaryContainer,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
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
  });

  final String requestId;
  final EditorState state;
  final EditorNotifier notifier;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return LayoutBuilder(
      builder: (context, c) {
        final request = _RequestTabs(
          requestId: requestId,
          item: state.item,
          notifier: notifier,
        );
        final response = _response(context, ref);
        // Side by side is cramped below tablet width; stack instead.
        return Column(
          children: [
            Expanded(child: request),
            const Divider(height: 1),
            Expanded(child: response),
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
                ScaffoldMessenger.maybeOf(context)?.showSnackBar(
                  SnackBar(content: Text(context.l10n.reResponseSaved)),
                );
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
              Tab(text: context.l10n.reTabParams),
              Tab(text: context.l10n.reTabHeaders),
              Tab(text: context.l10n.reTabAuth),
              Tab(text: context.l10n.reTabBody),
              Tab(text: context.l10n.reTabScripts),
              Tab(text: context.l10n.reTabAssertions),
              Tab(text: context.l10n.reTabSettings),
            ],
          ),
          Expanded(child: TabBarView(children: _views())),
        ],
      ),
    );
  }

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
