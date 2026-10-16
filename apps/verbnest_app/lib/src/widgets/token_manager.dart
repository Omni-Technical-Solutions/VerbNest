import 'package:material_ui/material_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../state/editor_state.dart';
import '../../l10n/l10n.dart';

String _when(BuildContext context, DateTime? t) {
  final l = context.l10n;
  if (t == null) return l.tokenNeverExpires;
  final left = t.difference(DateTime.now());
  if (left.isNegative) return l.tokenExpired;
  if (left.inMinutes < 1) return l.tokenExpiresSeconds(left.inSeconds);
  if (left.inHours < 1) return l.tokenExpiresMinutes(left.inMinutes);
  return l.tokenExpiresHours(left.inHours);
}

/// Lists the OAuth 2.0 tokens held for this app session and lets the user
/// delete them (FR-AUTH-003). Token values are never shown.
Future<void> showTokenManager(BuildContext context) => showDialog<void>(
  animationStyle: AnimationStyle.noAnimation,
  context: context,
  builder: (_) => const _TokenManager(),
);

class _TokenManager extends ConsumerStatefulWidget {
  const _TokenManager();

  @override
  ConsumerState<_TokenManager> createState() => _TokenManagerState();
}

class _TokenManagerState extends ConsumerState<_TokenManager> {
  @override
  Widget build(BuildContext context) {
    final cache = ref.read(oauthCacheProvider);
    final tokens = cache.entries;
    return AlertDialog(
      title: Text(context.l10n.tokensTitle),
      content: SizedBox(
        width: 460,
        child: tokens.isEmpty
            ? Text(context.l10n.tokensEmpty, key: const Key('tokens-empty'))
            : ListView(
                shrinkWrap: true,
                children: [
                  for (final t in tokens)
                    ListTile(
                      key: Key('token-${t.key.hashCode}'),
                      dense: true,
                      title: Text(
                        '${t.auth.grant.wire} · '
                        '${t.auth.clientId.isEmpty ? context.l10n.tokenNoClientId : t.auth.clientId}',
                      ),
                      subtitle: Text(
                        '${_when(context, t.token.expiresAt)}'
                        '${t.token.refreshToken != null ? ' · ${context.l10n.tokenHasRefresh}' : ''}'
                        '\n${t.auth.tokenUrl.isEmpty ? t.auth.authUrl : t.auth.tokenUrl}',
                      ),
                      isThreeLine: true,
                      trailing: IconButton(
                        tooltip: context.l10n.delete,
                        icon: const Icon(Icons.delete_outline),
                        onPressed: () => setState(() => cache.remove(t.key)),
                      ),
                    ),
                ],
              ),
      ),
      actions: [
        if (tokens.isNotEmpty)
          TextButton(
            key: const Key('tokens-clear'),
            onPressed: () => setState(cache.clear),
            child: Text(context.l10n.tokensDeleteAll),
          ),
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: Text(context.l10n.close),
        ),
      ],
    );
  }
}
