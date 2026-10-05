import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:postit_core/postit_core.dart';

import 'synced_field.dart';
import 'token_manager.dart';

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
    'digest',
    'jwt',
    'awsv4',
  ];

  void _set(Auth a) => onChanged(a);

  Auth _fresh(String type) => switch (type) {
    'none' => const NoAuth(),
    'bearer' => const BearerAuth(token: ''),
    'basic' => const BasicAuth(username: '', password: ''),
    'apikey' => const ApiKeyAuth(key: '', value: ''),
    'oauth2' => const OAuth2Auth(grant: OAuth2Grant.clientCredentials),
    'digest' => const DigestAuth(username: '', password: ''),
    'jwt' => const JwtAuth(),
    'awsv4' => const AwsV4Auth(),
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
          DigestAuth() => [
            _field(
              'Username',
              auth.username,
              (v) => DigestAuth(username: v, password: auth.password),
            ),
            _field(
              'Password',
              auth.password,
              (v) => DigestAuth(username: auth.username, password: v),
              obscure: true,
            ),
            const Text(
              'The request is sent once without credentials; the server '
              'challenge is answered automatically.',
            ),
          ],
          JwtAuth() => _jwt(auth),
          AwsV4Auth() => [
            _field(
              'Access key',
              auth.accessKey,
              (v) => auth.copyWith(accessKey: v),
            ),
            _field(
              'Secret key',
              auth.secretKey,
              (v) => auth.copyWith(secretKey: v),
              obscure: true,
            ),
            _field('Region', auth.region, (v) => auth.copyWith(region: v)),
            _field('Service', auth.service, (v) => auth.copyWith(service: v)),
            _field(
              'Session token',
              auth.sessionToken,
              (v) => auth.copyWith(sessionToken: v),
              obscure: true,
            ),
          ],
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
  Widget _field(
    String label,
    String value,
    Auth Function(String) change, {
    bool obscure = false,
  }) => Padding(
    padding: const EdgeInsets.only(bottom: 8),
    child: SyncedTextField(
      key: Key('auth-$label'),
      label: label,
      value: value,
      obscure: obscure,
      onChanged: (v) => _set(change(v)),
    ),
  );

  List<Widget> _jwt(JwtAuth a) => [
    DropdownButton<JwtAlgorithm>(
      key: const Key('jwt-algorithm'),
      value: a.algorithm,
      items: [
        for (final g in JwtAlgorithm.values)
          DropdownMenuItem(value: g, child: Text(g.label)),
      ],
      onChanged: (g) {
        if (g != null) _set(a.copyWith(algorithm: g));
      },
    ),
    const SizedBox(height: 8),
    _field('Secret', a.secret, (v) => a.copyWith(secret: v), obscure: true),
    _field('Payload (JSON)', a.payload, (v) => a.copyWith(payload: v)),
    _field('Header prefix', a.prefix, (v) => a.copyWith(prefix: v)),
    const Text('A token is signed for each send; iat is added if missing.'),
  ];

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

    final needsToken = a.grant != OAuth2Grant.implicit;
    return [
      DropdownButton<OAuth2Grant>(
        key: const Key('oauth-grant'),
        value: a.grant,
        items: const [
          DropdownMenuItem(
            value: OAuth2Grant.clientCredentials,
            child: Text('Client credentials'),
          ),
          DropdownMenuItem(
            value: OAuth2Grant.password,
            child: Text('Password'),
          ),
          DropdownMenuItem(
            value: OAuth2Grant.authorizationCode,
            child: Text('Authorization code (browser)'),
          ),
          DropdownMenuItem(
            value: OAuth2Grant.implicit,
            child: Text('Implicit (browser)'),
          ),
        ],
        onChanged: (g) {
          if (g != null) _set(a.copyWith(grant: g));
        },
      ),
      const SizedBox(height: 8),
      if (a.interactive)
        field('Auth URL', a.authUrl, (v) => a.copyWith(authUrl: v)),
      if (needsToken)
        field('Token URL', a.tokenUrl, (v) => a.copyWith(tokenUrl: v)),
      field('Client ID', a.clientId, (v) => a.copyWith(clientId: v)),
      if (needsToken)
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
      if (a.grant == OAuth2Grant.authorizationCode)
        SwitchListTile(
          key: const Key('oauth-pkce'),
          contentPadding: EdgeInsets.zero,
          title: const Text('Use PKCE'),
          value: a.usePkce,
          onChanged: (v) => _set(a.copyWith(usePkce: v)),
        ),
      if (a.interactive)
        const Padding(
          padding: EdgeInsets.only(bottom: 8),
          child: Text(
            'Sending opens your browser to sign in. The redirect URL is '
            'http://127.0.0.1:<port>/callback with a random port; if your '
            'provider needs a fixed redirect URL, register the loopback '
            'address with a wildcard port.',
          ),
        ),
      Align(
        alignment: AlignmentDirectional.centerStart,
        child: Consumer(
          builder: (context, ref, _) => TextButton.icon(
            key: const Key('oauth-tokens'),
            onPressed: () => showTokenManager(context),
            icon: const Icon(Icons.vpn_key_outlined),
            label: const Text('Tokens…'),
          ),
        ),
      ),
      SwitchListTile(
        contentPadding: EdgeInsets.zero,
        title: const Text('Send client credentials in the body'),
        value: a.clientAuthInBody,
        onChanged: (v) => _set(a.copyWith(clientAuthInBody: v)),
      ),
    ];
  }
}
