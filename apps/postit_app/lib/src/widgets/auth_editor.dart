import 'package:flutter/material.dart';
import 'package:postit_core/postit_core.dart';

import 'synced_field.dart';

/// Auth picker and fields, shared by requests and containers (FR-AUTH-001).
class AuthEditor extends StatelessWidget {
  const AuthEditor({
    super.key,
    required this.auth,
    required this.onChanged,
    this.inheritText = 'Uses the auth of the enclosing folder or collection.',
  });

  final Auth auth;
  final ValueChanged<Auth> onChanged;
  final String inheritText;

  static const _types = [
    'inherit',
    'none',
    'bearer',
    'basic',
    'apikey',
    'oauth2',
  ];

  void _set(Auth a) => onChanged(a);

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
    final auth = this.auth;
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
          InheritAuth() => [Text(inheritText)],
          NoAuth() => [const Text('No authorization is added.')],
          RawAuth() => [
            Text('Auth type "${auth.type}" is kept but not editable yet.'),
          ],
        },
      ],
    );
  }
}

extension on AuthEditor {
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
