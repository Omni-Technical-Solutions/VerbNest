import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../state/editor_state.dart';

String _when(DateTime? t) {
  if (t == null) return 'does not expire';
  final left = t.difference(DateTime.now());
  if (left.isNegative) return 'expired';
  if (left.inMinutes < 1) return 'expires in ${left.inSeconds} s';
  if (left.inHours < 1) return 'expires in ${left.inMinutes} min';
  return 'expires in ${left.inHours} h';
}

/// Lists the OAuth 2.0 tokens held for this app session and lets the user
/// delete them (FR-AUTH-003). Token values are never shown.
Future<void> showTokenManager(BuildContext context) =>
    showDialog<void>(context: context, builder: (_) => const _TokenManager());

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
      title: const Text('OAuth 2.0 tokens'),
      content: SizedBox(
        width: 460,
        child: tokens.isEmpty
            ? const Text(
                'No tokens yet. They are kept in memory until you quit the app.',
                key: Key('tokens-empty'),
              )
            : ListView(
                shrinkWrap: true,
                children: [
                  for (final t in tokens)
                    ListTile(
                      key: Key('token-${t.key.hashCode}'),
                      dense: true,
                      title: Text(
                        '${t.auth.grant.wire} · '
                        '${t.auth.clientId.isEmpty ? 'no client id' : t.auth.clientId}',
                      ),
                      subtitle: Text(
                        '${_when(t.token.expiresAt)}'
                        '${t.token.refreshToken != null ? ' · has refresh token' : ''}'
                        '\n${t.auth.tokenUrl.isEmpty ? t.auth.authUrl : t.auth.tokenUrl}',
                      ),
                      isThreeLine: true,
                      trailing: IconButton(
                        tooltip: 'Delete',
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
            child: const Text('Delete all'),
          ),
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Close'),
        ),
      ],
    );
  }
}
