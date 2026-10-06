import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:verbnest_core/verbnest_core.dart';

import 'synced_field.dart';
import 'token_manager.dart';
import '../../l10n/l10n.dart';

/// Auth picker and fields, shared by requests and containers (FR-AUTH-001).
class AuthEditor extends StatelessWidget {
  const AuthEditor({
    super.key,
    required this.auth,
    required this.onChanged,
    this.inheritText,
  });

  final Auth auth;
  final ValueChanged<Auth> onChanged;
  final String? inheritText;

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
              label: context.l10n.authToken,
              value: auth.token,
              onChanged: (v) => _set(BearerAuth(token: v)),
            ),
          ],
          BasicAuth() => [
            SyncedTextField(
              key: const Key('auth-user'),
              label: context.l10n.authUsername,
              value: auth.username,
              onChanged: (v) =>
                  _set(BasicAuth(username: v, password: auth.password)),
            ),
            const SizedBox(height: 8),
            SyncedTextField(
              key: const Key('auth-pass'),
              label: context.l10n.authPassword,
              obscure: true,
              value: auth.password,
              onChanged: (v) =>
                  _set(BasicAuth(username: auth.username, password: v)),
            ),
          ],
          ApiKeyAuth() => [
            SyncedTextField(
              label: context.l10n.authKey,
              value: auth.key,
              onChanged: (v) => _set(
                ApiKeyAuth(key: v, value: auth.value, addTo: auth.addTo),
              ),
            ),
            const SizedBox(height: 8),
            SyncedTextField(
              label: context.l10n.authValue,
              value: auth.value,
              onChanged: (v) =>
                  _set(ApiKeyAuth(key: auth.key, value: v, addTo: auth.addTo)),
            ),
            const SizedBox(height: 8),
            SegmentedButton<ApiKeyLocation>(
              segments: [
                ButtonSegment(
                  value: ApiKeyLocation.header,
                  label: Text(context.l10n.authHeader),
                ),
                ButtonSegment(
                  value: ApiKeyLocation.query,
                  label: Text(context.l10n.authQuery),
                ),
              ],
              selected: {auth.addTo},
              onSelectionChanged: (s) => _set(
                ApiKeyAuth(key: auth.key, value: auth.value, addTo: s.first),
              ),
            ),
          ],
          OAuth2Auth() => _oauth2(context, auth),
          DigestAuth() => [
            _field(
              'Username',
              context.l10n.authUsername,
              auth.username,
              (v) => DigestAuth(username: v, password: auth.password),
            ),
            _field(
              'Password',
              context.l10n.authPassword,
              auth.password,
              (v) => DigestAuth(username: auth.username, password: v),
              obscure: true,
            ),
            Text(context.l10n.authDigestHint),
          ],
          JwtAuth() => _jwt(context, auth),
          AwsV4Auth() => [
            _field(
              'Access key',
              context.l10n.authAccessKey,
              auth.accessKey,
              (v) => auth.copyWith(accessKey: v),
            ),
            _field(
              'Secret key',
              context.l10n.authSecretKey,
              auth.secretKey,
              (v) => auth.copyWith(secretKey: v),
              obscure: true,
            ),
            _field(
              'Region',
              context.l10n.authRegion,
              auth.region,
              (v) => auth.copyWith(region: v),
            ),
            _field(
              'Service',
              context.l10n.authService,
              auth.service,
              (v) => auth.copyWith(service: v),
            ),
            _field(
              'Session token',
              context.l10n.authSessionToken,
              auth.sessionToken,
              (v) => auth.copyWith(sessionToken: v),
              obscure: true,
            ),
          ],
          InheritAuth() => [Text(inheritText ?? context.l10n.authInherit)],
          NoAuth() => [Text(context.l10n.authNone)],
          RawAuth() => [Text(context.l10n.authRaw(auth.type))],
        },
      ],
    );
  }
}

extension on AuthEditor {
  Widget _field(
    String id,
    String label,
    String value,
    Auth Function(String) change, {
    bool obscure = false,
  }) => Padding(
    padding: const EdgeInsets.only(bottom: 8),
    child: SyncedTextField(
      key: Key('auth-$id'),
      label: label,
      value: value,
      obscure: obscure,
      onChanged: (v) => _set(change(v)),
    ),
  );

  List<Widget> _jwt(BuildContext context, JwtAuth a) => [
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
    _field(
      'Secret',
      context.l10n.authSecret,
      a.secret,
      (v) => a.copyWith(secret: v),
      obscure: true,
    ),
    _field(
      'Payload (JSON)',
      context.l10n.authPayload,
      a.payload,
      (v) => a.copyWith(payload: v),
    ),
    _field(
      'Header prefix',
      context.l10n.authHeaderPrefix,
      a.prefix,
      (v) => a.copyWith(prefix: v),
    ),
    Text(context.l10n.authJwtHint),
  ];

  List<Widget> _oauth2(BuildContext context, OAuth2Auth a) {
    Widget field(
      String id,
      String label,
      String value,
      OAuth2Auth Function(String) change, {
      bool obscure = false,
    }) => Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: SyncedTextField(
        key: Key('oauth-$id'),
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
        items: [
          DropdownMenuItem(
            value: OAuth2Grant.clientCredentials,
            child: Text(context.l10n.oauthClientCredentials),
          ),
          DropdownMenuItem(
            value: OAuth2Grant.password,
            child: Text(context.l10n.oauthPassword),
          ),
          DropdownMenuItem(
            value: OAuth2Grant.authorizationCode,
            child: Text(context.l10n.oauthAuthCode),
          ),
          DropdownMenuItem(
            value: OAuth2Grant.implicit,
            child: Text(context.l10n.oauthImplicit),
          ),
        ],
        onChanged: (g) {
          if (g != null) _set(a.copyWith(grant: g));
        },
      ),
      const SizedBox(height: 8),
      if (a.interactive)
        field(
          'Auth URL',
          context.l10n.oauthAuthUrl,
          a.authUrl,
          (v) => a.copyWith(authUrl: v),
        ),
      if (needsToken)
        field(
          'Token URL',
          context.l10n.oauthTokenUrl,
          a.tokenUrl,
          (v) => a.copyWith(tokenUrl: v),
        ),
      field(
        'Client ID',
        context.l10n.oauthClientId,
        a.clientId,
        (v) => a.copyWith(clientId: v),
      ),
      if (needsToken)
        field(
          'Client secret',
          context.l10n.oauthClientSecret,
          a.clientSecret,
          (v) => a.copyWith(clientSecret: v),
          obscure: true,
        ),
      field(
        'Scope',
        context.l10n.oauthScope,
        a.scope,
        (v) => a.copyWith(scope: v),
      ),
      if (a.grant == OAuth2Grant.password) ...[
        field(
          'Username',
          context.l10n.authUsername,
          a.username,
          (v) => a.copyWith(username: v),
        ),
        field(
          'Password',
          context.l10n.authPassword,
          a.password,
          (v) => a.copyWith(password: v),
          obscure: true,
        ),
      ],
      if (a.grant == OAuth2Grant.authorizationCode)
        SwitchListTile(
          key: const Key('oauth-pkce'),
          contentPadding: EdgeInsets.zero,
          title: Text(context.l10n.oauthPkce),
          value: a.usePkce,
          onChanged: (v) => _set(a.copyWith(usePkce: v)),
        ),
      if (a.interactive)
        Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: Text(context.l10n.oauthBrowserHint),
        ),
      Align(
        alignment: AlignmentDirectional.centerStart,
        child: Consumer(
          builder: (context, ref, _) => TextButton.icon(
            key: const Key('oauth-tokens'),
            onPressed: () => showTokenManager(context),
            icon: const Icon(Icons.vpn_key_outlined),
            label: Text(context.l10n.oauthTokens),
          ),
        ),
      ),
      SwitchListTile(
        contentPadding: EdgeInsets.zero,
        title: Text(context.l10n.oauthBodyCreds),
        value: a.clientAuthInBody,
        onChanged: (v) => _set(a.copyWith(clientAuthInBody: v)),
      ),
    ];
  }
}
