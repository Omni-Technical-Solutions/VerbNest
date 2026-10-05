import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:postit_core/postit_core.dart';
import 'package:postit_import/postit_import.dart';

import '../state/editor_state.dart';
import '../state/file_port.dart';
import '../state/prefs.dart';
import '../state/session.dart';
import '../state/settings_state.dart';
import '../state/var_text.dart';
import '../state/variables.dart';
import 'name_dialog.dart';
import 'assertions_editor.dart';
import 'scripts_editor.dart';
import 'auth_editor.dart';
import 'env_selector.dart';
import 'kv_editor.dart';
import 'response_view.dart';
import 'request_extras.dart';
import 'graphql_editor.dart';
import 'realtime_dialog.dart';
import 'synced_field.dart';
import '../../l10n/l10n.dart';

const _customMethod = '\u0000custom';

const httpMethods = [
  'GET',
  'POST',
  'PUT',
  'PATCH',
  'DELETE',
  'HEAD',
  'OPTIONS',
];

/// Editor for one request: URL bar, request tabs and the response.
class RequestEditor extends ConsumerWidget {
  const RequestEditor({super.key, required this.requestId});

  final String requestId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(editorProvider(requestId));
    final notifier = ref.read(editorProvider(requestId).notifier);
    final item = state.item;
    final session = ref.read(sessionProvider);
    final envId = ref.watch(activeEnvProvider);

    return VariableContext(
      scopes: () => buildScopes(session, requestId: requestId, envId: envId),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Align(
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
          ),
          _urlBar(context, ref, state, notifier),
          if (state.pendingUnresolved.isNotEmpty)
            _pendingBanner(context, ref, state, notifier),
          if (state.unresolved.isNotEmpty)
            _banner(
              context,
              context.l10n.reUndefined(
                state.unresolved.map((n) => '{{$n}}').join(', '),
              ),
            ),
          for (final w in state.warnings) _banner(context, w),
          Expanded(
            child: LayoutBuilder(
              builder: (context, c) {
                final request = _requestTabs(context, item, notifier);
                final port = ref.read(filePortProvider);
                final r = state.response;
                final response = ResponseView(
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
                              SnackBar(
                                content: Text(context.l10n.reResponseSaved),
                              ),
                            );
                          }
                        },
                );
                // Side by side is cramped below tablet width; stack instead.
                return Column(
                  children: [
                    Expanded(child: request),
                    const Divider(height: 1),
                    Expanded(child: response),
                  ],
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _pendingBanner(
    BuildContext context,
    WidgetRef ref,
    EditorState state,
    EditorNotifier notifier,
  ) => Container(
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

  Widget _banner(BuildContext context, String text) => Container(
    color: Theme.of(context).colorScheme.tertiaryContainer,
    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
    child: Text(text, key: const Key('banner')),
  );

  Widget _urlBar(
    BuildContext context,
    WidgetRef ref,
    EditorState state,
    EditorNotifier notifier,
  ) {
    final item = state.item;
    return Padding(
      padding: const EdgeInsets.all(8),
      child: Row(
        children: [
          DropdownButton<String>(
            key: const Key('method'),
            value: httpMethods.contains(item.method) ? item.method : null,
            hint: Text(item.method),
            underline: const SizedBox.shrink(),
            items: [
              for (final m in httpMethods)
                DropdownMenuItem(value: m, child: Text(m)),
              DropdownMenuItem(
                value: _customMethod,
                child: Text(context.l10n.reCustom),
              ),
            ],
            onChanged: (m) async {
              if (m == null) return;
              if (m != _customMethod) {
                notifier.edit((i) => i.copyWith(method: m));
                return;
              }
              final custom = await askName(
                context,
                title: context.l10n.reCustomMethod,
                initial: httpMethods.contains(item.method) ? '' : item.method,
                action: context.l10n.reSet,
              );
              if (custom != null) {
                notifier.edit(
                  (i) => i.copyWith(method: custom.trim().toUpperCase()),
                );
              }
            },
          ),
          const SizedBox(width: 8),
          Expanded(
            child: SyncedTextField(
              key: const Key('url'),
              value: item.url,
              hint: 'https://example.com/path?query={{var}}',
              variables: true,
              onChanged: (u) {
                if (looksLikeCurl(u)) {
                  try {
                    final c = parseCurl(u).item;
                    notifier.edit(
                      (i) => i.copyWith(
                        method: c.method,
                        url: c.url,
                        params: c.params,
                        headers: c.headers,
                        body: c.body,
                        auth: c.auth,
                        settings: c.settings,
                      ),
                    );
                    return;
                  } on FormatException {
                    // Still typing; keep the text as a plain URL.
                  }
                }
                notifier.edit((i) => _withUrl(i, u));
              },
            ),
          ),
          const SizedBox(width: 8),
          PopupMenuButton<LiveKind>(
            key: const Key('live'),
            tooltip: context.l10n.reLiveTooltip,
            icon: const Icon(Icons.sync_alt),
            onSelected: (kind) => showDialog<void>(
              context: context,
              barrierDismissible: false,
              builder: (_) => RealtimeDialog(
                sse: kind != LiveKind.websocket,
                title: switch (kind) {
                  LiveKind.websocket => context.l10n.reLiveWs,
                  LiveKind.sse => context.l10n.reLiveSseTitle,
                  LiveKind.graphqlSubscription => context.l10n.reLiveSub,
                },
                connect: () => notifier.connectRealtime(kind),
                onSave: (text) async {
                  final port = ref.read(filePortProvider);
                  await port.save(
                    'live-log.txt',
                    Uint8List.fromList(utf8.encode(text)),
                    mime: 'text/plain',
                  );
                },
              ),
            ),
            itemBuilder: (_) => [
              PopupMenuItem(
                value: LiveKind.websocket,
                child: Text(context.l10n.reLiveWs),
              ),
              PopupMenuItem(
                value: LiveKind.sse,
                child: Text(context.l10n.reLiveSse),
              ),
              if (item.body is GraphqlBody)
                PopupMenuItem(
                  value: LiveKind.graphqlSubscription,
                  child: Text(context.l10n.reLiveSub),
                ),
            ],
          ),
          state.sending
              ? FilledButton.tonal(
                  key: const Key('cancel'),
                  onPressed: notifier.cancel,
                  child: Text(context.l10n.reCancel),
                )
              : FilledButton(
                  key: const Key('send'),
                  onPressed: notifier.send,
                  child: Text(context.l10n.reSend),
                ),
        ],
      ),
    );
  }

  /// URL edited: refresh the params table from the query and the path
  /// variable rows from `/:name` segments, keeping disabled rows and values.
  static HttpRequestItem _withUrl(HttpRequestItem i, String url) {
    final fromUrl = UrlText.params(url);
    final disabled = i.params.where((p) => !p.enabled);
    final oldVars = {for (final v in i.pathVars) v.key: v};
    return i.copyWith(
      url: url,
      params: [...fromUrl, ...disabled],
      pathVars: [
        for (final n in UrlText.pathVariables(url))
          oldVars[n] ?? KeyValue(key: n),
      ],
    );
  }

  /// Params table edited: rewrite the query to match.
  static HttpRequestItem _withParams(
    HttpRequestItem i,
    List<KeyValue> params,
  ) => i.copyWith(params: params, url: UrlText.withParams(i.url, params));

  Widget _requestTabs(
    BuildContext context,
    HttpRequestItem item,
    EditorNotifier notifier,
  ) {
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
          Expanded(
            child: TabBarView(
              children: [
                _paramsTab(context, item, notifier),
                _HeadersTab(
                  item: item,
                  notifier: notifier,
                  requestId: requestId,
                ),
                AuthEditor(
                  auth: item.auth,
                  onChanged: (a) => notifier.edit((i) => i.copyWith(auth: a)),
                ),
                _BodyTab(item: item, notifier: notifier),
                Consumer(
                  builder: (context, ref, _) => ScriptsEditor(
                    scripts: item.scripts,
                    fontSize: ref.watch(prefsProvider).editorFontSize,
                    onChanged: (s) =>
                        notifier.edit((i) => i.copyWith(scripts: s)),
                  ),
                ),
                AssertionsEditor(
                  assertions: item.assertions,
                  onChanged: (a) =>
                      notifier.edit((i) => i.copyWith(assertions: a)),
                ),
                _SettingsTab(item: item, notifier: notifier),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _paramsTab(
    BuildContext context,
    HttpRequestItem item,
    EditorNotifier notifier,
  ) {
    return Column(
      children: [
        Expanded(
          child: KeyValueEditor(
            idPrefix: 'params',
            rows: item.params,
            onChanged: (p) => notifier.edit((i) => _withParams(i, p)),
          ),
        ),
        if (item.pathVars.isNotEmpty) ...[
          Padding(
            padding: const EdgeInsets.all(8),
            child: Text(context.l10n.rePathVars),
          ),
          SizedBox(
            height: 40.0 * item.pathVars.length + 8,
            child: Column(
              children: [
                for (var n = 0; n < item.pathVars.length; n++)
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 8),
                    child: Row(
                      children: [
                        SizedBox(width: 120, child: Text(item.pathVars[n].key)),
                        Expanded(
                          child: SyncedTextField(
                            key: ValueKey('pathvar-$n'),
                            value: item.pathVars[n].value,
                            hint: context.l10n.reValue,
                            onChanged: (v) => notifier.edit((i) {
                              final next = [...i.pathVars];
                              next[n] = next[n].copyWith(value: v);
                              return i.copyWith(pathVars: next);
                            }),
                          ),
                        ),
                      ],
                    ),
                  ),
              ],
            ),
          ),
        ],
      ],
    );
  }
}

class _HeadersTab extends ConsumerWidget {
  const _HeadersTab({
    required this.item,
    required this.notifier,
    required this.requestId,
  });

  final HttpRequestItem item;
  final EditorNotifier notifier;
  final String requestId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final repo = ref.read(repositoryProvider);
    final defaults = ref.watch(httpDefaultsProvider);
    final auto = autoHeaders(
      item,
      effectiveAuth(item.auth, repo.authChain(requestId)),
      autoDecompress: item.settings.autoDecompress ?? defaults.autoDecompress,
    );
    return Column(
      children: [
        ExpansionTile(
          key: const Key('auto-headers'),
          dense: true,
          title: Text(context.l10n.reGenerated(auto.length)),
          subtitle: Text(context.l10n.reGeneratedHint),
          children: [
            for (final h in auto)
              ListTile(
                dense: true,
                visualDensity: VisualDensity.compact,
                title: Text('${h.$1}: ${h.$2}'),
              ),
          ],
        ),
        Expanded(
          child: KeyValueEditor(
            idPrefix: 'headers',
            rows: item.headers,
            keySuggestions: headerNames,
            valueSuggestions: const {'content-type': contentTypes},
            onChanged: (h) => notifier.edit((i) => i.copyWith(headers: h)),
          ),
        ),
      ],
    );
  }
}

class _BodyTab extends ConsumerWidget {
  const _BodyTab({required this.item, required this.notifier});

  final HttpRequestItem item;
  final EditorNotifier notifier;

  static const _modes = [
    'none',
    'json',
    'text',
    'xml',
    'html',
    'javascript',
    'graphql',
    'urlencoded',
    'form',
    'binary',
  ];

  RequestBody _fresh(String mode) {
    for (final l in RawBodyLanguage.values) {
      if (l.name == mode) return RawBody(l, '');
    }
    return switch (mode) {
      'graphql' => const GraphqlBody(),
      'urlencoded' => const UrlEncodedBody([]),
      'form' => const FormDataBody([]),
      'binary' => const BinaryBody(null),
      _ => const NoBody(),
    };
  }

  void _set(RequestBody b) => notifier.edit((i) => i.copyWith(body: b));

  /// Lets the user pick a file and stores it in the workspace.
  Future<({String id, String name})?> _store(WidgetRef ref) async {
    final f = await ref.read(filePortProvider).pick();
    if (f == null) return null;
    final name = safeFileName(f.name);
    final id = ref
        .read(repositoryProvider)
        .addAttachment(name, f.bytes, mime: f.mime);
    return (id: id, name: name);
  }

  Widget _binary(BuildContext context, WidgetRef ref, BinaryBody body) {
    final id = body.attachmentId;
    final info = id == null
        ? null
        : ref.read(repositoryProvider).attachment(id);
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            key: const Key('binary-info'),
            info == null
                ? context.l10n.reNoFile
                : context.l10n.reFileInfo(info.name, info.size),
          ),
          const SizedBox(height: 8),
          FilledButton.tonalIcon(
            key: const Key('binary-pick'),
            icon: const Icon(Icons.upload_file),
            label: Text(
              info == null
                  ? context.l10n.reChooseFile
                  : context.l10n.reReplaceFile,
            ),
            onPressed: () async {
              final stored = await _store(ref);
              if (stored != null) _set(BinaryBody(stored.id));
            },
          ),
          if (info != null)
            TextButton(
              key: const Key('binary-clear'),
              onPressed: () => _set(const BinaryBody(null)),
              child: Text(context.l10n.reRemoveFile),
            ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final body = item.body;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12),
          child: DropdownButton<String>(
            key: const Key('body-mode'),
            value: _modes.contains(body.mode) ? body.mode : null,
            hint: Text(body.mode),
            items: [
              for (final m in _modes)
                DropdownMenuItem(value: m, child: Text(m)),
            ],
            onChanged: (m) {
              if (m == null || m == body.mode) return;
              // A GraphQL operation is a POST; a GET with a body is rarely meant.
              notifier.edit(
                (i) => i.copyWith(
                  body: _fresh(m),
                  method: m == 'graphql' && i.method == 'GET'
                      ? 'POST'
                      : i.method,
                ),
              );
            },
          ),
        ),
        Expanded(
          child: switch (body) {
            RawBody() => Padding(
              padding: const EdgeInsets.all(8),
              child: SyncedTextField(
                key: const Key('body-text'),
                value: body.text,
                variables: true,
                monospace: true,
                expands: true,
                onChanged: (v) => _set(RawBody(body.language, v)),
              ),
            ),
            GraphqlBody() => GraphqlEditor(
              body: body,
              url: item.url,
              notifier: notifier,
              onChanged: _set,
            ),
            UrlEncodedBody() => KeyValueEditor(
              idPrefix: 'urlencoded',
              rows: body.fields,
              onChanged: (f) => _set(UrlEncodedBody(f)),
            ),
            FormDataBody() => KeyValueEditor(
              idPrefix: 'form',
              allowBulk: false,
              onPickFile: (row) async {
                final stored = await _store(ref);
                if (stored == null) return null;
                return row.copyWith(
                  type: KeyValueType.file,
                  value: attachmentRef(stored.id, stored.name),
                );
              },
              rows: body.fields,
              onChanged: (f) => _set(FormDataBody(f)),
            ),
            BinaryBody() => _binary(context, ref, body),
            NoBody() => Center(child: Text(context.l10n.reNoBody)),
          },
        ),
      ],
    );
  }
}

class _SettingsTab extends StatelessWidget {
  const _SettingsTab({required this.item, required this.notifier});

  final HttpRequestItem item;
  final EditorNotifier notifier;

  void _set(RequestSettings s) => notifier.edit((i) => i.copyWith(settings: s));

  @override
  Widget build(BuildContext context) {
    final s = item.settings;
    return ListView(
      padding: const EdgeInsets.all(12),
      children: [
        DropdownButtonFormField<String>(
          key: const Key('http-version'),
          initialValue: s.httpVersion ?? 'auto',
          decoration: InputDecoration(
            labelText: context.l10n.reHttpVersion,
            helperText: context.l10n.reHttp2Hint,
          ),
          items: [
            DropdownMenuItem(
              value: 'auto',
              child: Text(context.l10n.reHttpAuto),
            ),
            DropdownMenuItem(value: '1.1', child: Text(context.l10n.reHttp11)),
            DropdownMenuItem(value: '2', child: Text(context.l10n.reHttp2)),
          ],
          onChanged: (v) =>
              _set(s.copyWith(httpVersion: v == 'auto' ? null : v)),
        ),
        const SizedBox(height: 8),
        SyncedTextField(
          key: const Key('timeout'),
          label: context.l10n.reTimeout,
          value: s.timeoutMs?.toString() ?? '',
          onChanged: (v) => _set(s.copyWith(timeoutMs: int.tryParse(v.trim()))),
        ),
        const SizedBox(height: 8),
        SyncedTextField(
          key: const Key('max-redirects'),
          label: context.l10n.reMaxRedirects,
          value: s.maxRedirects?.toString() ?? '',
          onChanged: (v) =>
              _set(s.copyWith(maxRedirects: int.tryParse(v.trim()))),
        ),
        SwitchListTile(
          key: const Key('verify-tls'),
          title: Text(context.l10n.reVerifyTls),
          value: s.verifyTls ?? true,
          onChanged: (v) => _set(s.copyWith(verifyTls: v)),
        ),
        SwitchListTile(
          key: const Key('follow-redirects'),
          title: Text(context.l10n.reFollow),
          value: s.followRedirects ?? true,
          onChanged: (v) => _set(s.copyWith(followRedirects: v)),
        ),
        SwitchListTile(
          key: const Key('keep-method'),
          title: Text(context.l10n.reKeepMethod),
          value: s.keepMethodOnRedirect ?? false,
          onChanged: (v) => _set(s.copyWith(keepMethodOnRedirect: v)),
        ),
        SwitchListTile(
          key: const Key('strip-auth'),
          title: Text(context.l10n.reStripAuth),
          value: s.stripAuthCrossOrigin ?? true,
          onChanged: (v) => _set(s.copyWith(stripAuthCrossOrigin: v)),
        ),
        SwitchListTile(
          key: const Key('send-cookies'),
          title: Text(context.l10n.reCookies),
          value: s.sendCookies ?? true,
          onChanged: (v) => _set(s.copyWith(sendCookies: v)),
        ),
        SwitchListTile(
          key: const Key('use-proxy'),
          title: Text(context.l10n.reUseProxy),
          subtitle: Text(context.l10n.reUseProxyHint),
          value: s.useProxy ?? true,
          onChanged: (v) => _set(s.copyWith(useProxy: v)),
        ),
        SwitchListTile(
          key: const Key('auto-decompress'),
          title: Text(context.l10n.reDecompress),
          value: s.autoDecompress ?? true,
          onChanged: (v) => _set(s.copyWith(autoDecompress: v)),
        ),
      ],
    );
  }
}
