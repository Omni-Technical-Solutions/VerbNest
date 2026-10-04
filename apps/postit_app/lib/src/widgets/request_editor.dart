import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:postit_core/postit_core.dart';

import '../state/editor_state.dart';
import 'env_selector.dart';
import 'kv_editor.dart';
import 'response_view.dart';
import 'synced_field.dart';

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

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Align(
          alignment: Alignment.centerRight,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8),
            child: EnvSelector(requestId: requestId),
          ),
        ),
        _urlBar(context, state, notifier),
        if (state.unresolved.isNotEmpty)
          _banner(
            context,
            'Undefined variables: ${state.unresolved.map((n) => '{{$n}}').join(', ')}',
          ),
        for (final w in state.warnings) _banner(context, w),
        Expanded(
          child: LayoutBuilder(
            builder: (context, c) {
              final request = _requestTabs(item, notifier);
              final response = ResponseView(state: state);
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
    );
  }

  Widget _banner(BuildContext context, String text) => Container(
    color: Theme.of(context).colorScheme.tertiaryContainer,
    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
    child: Text(text, key: const Key('banner')),
  );

  Widget _urlBar(
    BuildContext context,
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
            ],
            onChanged: (m) {
              if (m != null) notifier.edit((i) => i.copyWith(method: m));
            },
          ),
          const SizedBox(width: 8),
          Expanded(
            child: SyncedTextField(
              key: const Key('url'),
              value: item.url,
              hint: 'https://example.com/path?query={{var}}',
              onChanged: (u) => notifier.edit((i) => _withUrl(i, u)),
            ),
          ),
          const SizedBox(width: 8),
          state.sending
              ? FilledButton.tonal(
                  key: const Key('cancel'),
                  onPressed: notifier.cancel,
                  child: const Text('Cancel'),
                )
              : FilledButton(
                  key: const Key('send'),
                  onPressed: notifier.send,
                  child: const Text('Send'),
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

  Widget _requestTabs(HttpRequestItem item, EditorNotifier notifier) {
    return DefaultTabController(
      length: 5,
      child: Column(
        children: [
          const TabBar(
            isScrollable: true,
            tabAlignment: TabAlignment.start,
            tabs: [
              Tab(text: 'Params'),
              Tab(text: 'Headers'),
              Tab(text: 'Auth'),
              Tab(text: 'Body'),
              Tab(text: 'Settings'),
            ],
          ),
          Expanded(
            child: TabBarView(
              children: [
                _paramsTab(item, notifier),
                KeyValueEditor(
                  idPrefix: 'headers',
                  rows: item.headers,
                  onChanged: (h) =>
                      notifier.edit((i) => i.copyWith(headers: h)),
                ),
                _AuthTab(item: item, notifier: notifier),
                _BodyTab(item: item, notifier: notifier),
                _SettingsTab(item: item, notifier: notifier),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _paramsTab(HttpRequestItem item, EditorNotifier notifier) {
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
          const Padding(
            padding: EdgeInsets.all(8),
            child: Text('Path variables'),
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
                            hint: 'Value',
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

class _AuthTab extends StatelessWidget {
  const _AuthTab({required this.item, required this.notifier});

  final HttpRequestItem item;
  final EditorNotifier notifier;

  static const _types = [
    'inherit',
    'none',
    'bearer',
    'basic',
    'apikey',
    'oauth2',
  ];

  void _set(Auth a) => notifier.edit((i) => i.copyWith(auth: a));

  Auth _fresh(String type) => switch (type) {
    'none' => const NoAuth(),
    'bearer' => const BearerAuth(token: ''),
    'basic' => const BasicAuth(username: '', password: ''),
    'apikey' => const ApiKeyAuth(key: '', value: ''),
    'oauth2' => const OAuth2Auth(grant: OAuth2Grant.clientCredentials),
    _ => const InheritAuth(),
  };

  @override
  Widget build(BuildContext context) {
    final auth = item.auth;
    return ListView(
      padding: const EdgeInsets.all(12),
      children: [
        DropdownButton<String>(
          key: const Key('auth-type'),
          value: _types.contains(auth.type) ? auth.type : null,
          hint: Text(auth.type),
          items: [
            for (final t in _types) DropdownMenuItem(value: t, child: Text(t)),
          ],
          onChanged: (t) {
            if (t != null && t != auth.type) _set(_fresh(t));
          },
        ),
        const SizedBox(height: 8),
        ...switch (auth) {
          BearerAuth() => [
            SyncedTextField(
              key: const Key('auth-token'),
              label: 'Token',
              value: auth.token,
              onChanged: (v) => _set(BearerAuth(token: v)),
            ),
          ],
          BasicAuth() => [
            SyncedTextField(
              key: const Key('auth-user'),
              label: 'Username',
              value: auth.username,
              onChanged: (v) =>
                  _set(BasicAuth(username: v, password: auth.password)),
            ),
            const SizedBox(height: 8),
            SyncedTextField(
              key: const Key('auth-pass'),
              label: 'Password',
              obscure: true,
              value: auth.password,
              onChanged: (v) =>
                  _set(BasicAuth(username: auth.username, password: v)),
            ),
          ],
          ApiKeyAuth() => [
            SyncedTextField(
              label: 'Key',
              value: auth.key,
              onChanged: (v) => _set(
                ApiKeyAuth(key: v, value: auth.value, addTo: auth.addTo),
              ),
            ),
            const SizedBox(height: 8),
            SyncedTextField(
              label: 'Value',
              value: auth.value,
              onChanged: (v) =>
                  _set(ApiKeyAuth(key: auth.key, value: v, addTo: auth.addTo)),
            ),
            const SizedBox(height: 8),
            SegmentedButton<ApiKeyLocation>(
              segments: const [
                ButtonSegment(
                  value: ApiKeyLocation.header,
                  label: Text('Header'),
                ),
                ButtonSegment(
                  value: ApiKeyLocation.query,
                  label: Text('Query'),
                ),
              ],
              selected: {auth.addTo},
              onSelectionChanged: (s) => _set(
                ApiKeyAuth(key: auth.key, value: auth.value, addTo: s.first),
              ),
            ),
          ],
          OAuth2Auth() => _oauth2(auth),
          InheritAuth() => [
            const Text('Uses the auth of the enclosing folder or collection.'),
          ],
          NoAuth() => [const Text('No authorization is added.')],
          RawAuth() => [
            Text('Auth type "${auth.type}" is kept but not editable yet.'),
          ],
        },
      ],
    );
  }
}

extension on _AuthTab {
  List<Widget> _oauth2(OAuth2Auth a) {
    Widget field(
      String label,
      String value,
      OAuth2Auth Function(String) change, {
      bool obscure = false,
    }) => Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: SyncedTextField(
        key: Key('oauth-$label'),
        label: label,
        value: value,
        obscure: obscure,
        onChanged: (v) => _set(change(v)),
      ),
    );

    return [
      SegmentedButton<OAuth2Grant>(
        segments: const [
          ButtonSegment(
            value: OAuth2Grant.clientCredentials,
            label: Text('Client credentials'),
          ),
          ButtonSegment(value: OAuth2Grant.password, label: Text('Password')),
        ],
        selected: {a.grant},
        onSelectionChanged: (s) => _set(a.copyWith(grant: s.first)),
      ),
      const SizedBox(height: 8),
      field('Token URL', a.tokenUrl, (v) => a.copyWith(tokenUrl: v)),
      field('Client ID', a.clientId, (v) => a.copyWith(clientId: v)),
      field(
        'Client secret',
        a.clientSecret,
        (v) => a.copyWith(clientSecret: v),
        obscure: true,
      ),
      field('Scope', a.scope, (v) => a.copyWith(scope: v)),
      if (a.grant == OAuth2Grant.password) ...[
        field('Username', a.username, (v) => a.copyWith(username: v)),
        field(
          'Password',
          a.password,
          (v) => a.copyWith(password: v),
          obscure: true,
        ),
      ],
      SwitchListTile(
        contentPadding: EdgeInsets.zero,
        title: const Text('Send client credentials in the body'),
        value: a.clientAuthInBody,
        onChanged: (v) => _set(a.copyWith(clientAuthInBody: v)),
      ),
    ];
  }
}

class _BodyTab extends StatelessWidget {
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
    'urlencoded',
    'form',
  ];

  RequestBody _fresh(String mode) {
    for (final l in RawBodyLanguage.values) {
      if (l.name == mode) return RawBody(l, '');
    }
    return switch (mode) {
      'urlencoded' => const UrlEncodedBody([]),
      'form' => const FormDataBody([]),
      _ => const NoBody(),
    };
  }

  void _set(RequestBody b) => notifier.edit((i) => i.copyWith(body: b));

  @override
  Widget build(BuildContext context) {
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
              if (m != null && m != body.mode) _set(_fresh(m));
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
                monospace: true,
                expands: true,
                onChanged: (v) => _set(RawBody(body.language, v)),
              ),
            ),
            UrlEncodedBody() => KeyValueEditor(
              idPrefix: 'urlencoded',
              rows: body.fields,
              onChanged: (f) => _set(UrlEncodedBody(f)),
            ),
            FormDataBody() => KeyValueEditor(
              idPrefix: 'form',
              rows: body.fields,
              onChanged: (f) => _set(FormDataBody(f)),
            ),
            BinaryBody() => const Center(
              child: Text('Binary bodies are kept but not editable yet.'),
            ),
            NoBody() => const Center(child: Text('This request has no body')),
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
    RequestSettings with_({
      Object? timeoutMs = _keep,
      Object? verifyTls = _keep,
      Object? followRedirects = _keep,
    }) => RequestSettings(
      timeoutMs: identical(timeoutMs, _keep) ? s.timeoutMs : timeoutMs as int?,
      verifyTls: identical(verifyTls, _keep) ? s.verifyTls : verifyTls as bool?,
      followRedirects: identical(followRedirects, _keep)
          ? s.followRedirects
          : followRedirects as bool?,
      maxRedirects: s.maxRedirects,
    );

    return ListView(
      padding: const EdgeInsets.all(12),
      children: [
        SyncedTextField(
          key: const Key('timeout'),
          label: 'Timeout (ms), empty = default',
          value: s.timeoutMs?.toString() ?? '',
          onChanged: (v) => _set(with_(timeoutMs: int.tryParse(v.trim()))),
        ),
        SwitchListTile(
          key: const Key('verify-tls'),
          title: const Text('Verify TLS certificates'),
          value: s.verifyTls ?? true,
          onChanged: (v) => _set(with_(verifyTls: v)),
        ),
        SwitchListTile(
          title: const Text('Follow redirects'),
          value: s.followRedirects ?? true,
          onChanged: (v) => _set(with_(followRedirects: v)),
        ),
      ],
    );
  }
}

const _keep = Object();
