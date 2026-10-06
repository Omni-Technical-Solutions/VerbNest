import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../state/network_state.dart';
import '../../l10n/l10n.dart';

/// Lists the saved cookies by domain; remove one, a domain or all of them.
class CookieManagerDialog extends ConsumerWidget {
  const CookieManagerDialog({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final cookies = ref.watch(cookiesProvider);
    final n = ref.read(cookiesProvider.notifier);
    final domains = <String>{for (final c in cookies) c.domain}.toList();
    return AlertDialog(
      title: Text(context.l10n.cookiesTitle),
      content: SizedBox(
        width: 520,
        height: 380,
        child: cookies.isEmpty
            ? Center(
                key: const Key('no-cookies'),
                child: Text(context.l10n.cookiesEmpty),
              )
            : ListView(
                children: [
                  for (final d in domains) ...[
                    ListTile(
                      dense: true,
                      title: Text(
                        d,
                        style: const TextStyle(fontWeight: FontWeight.w600),
                      ),
                      trailing: IconButton(
                        key: Key('clear-domain-$d'),
                        tooltip: context.l10n.cookiesDeleteDomain(d),
                        icon: const Icon(Icons.delete_sweep_outlined),
                        onPressed: () => n.removeDomain(d),
                      ),
                    ),
                    for (final c in cookies.where((c) => c.domain == d))
                      ListTile(
                        key: Key('cookie-${c.id}'),
                        dense: true,
                        visualDensity: VisualDensity.compact,
                        title: Text('${c.name} = ${c.value}'),
                        subtitle: Text(
                          [
                            context.l10n.cookiePath(c.path),
                            if (c.secure) 'Secure',
                            if (c.httpOnly) 'HttpOnly',
                            if (c.sameSite != null) 'SameSite=${c.sameSite}',
                            c.expires == null
                                ? context.l10n.cookieSession
                                : context.l10n.cookieExpires(
                                    '${c.expires!.toLocal()}',
                                  ),
                          ].join(' · '),
                        ),
                        trailing: IconButton(
                          tooltip: context.l10n.delete,
                          icon: const Icon(Icons.close),
                          onPressed: () => n.remove(c),
                        ),
                      ),
                  ],
                ],
              ),
      ),
      actions: [
        TextButton(
          key: const Key('clear-cookies'),
          onPressed: cookies.isEmpty ? null : n.clear,
          child: Text(context.l10n.deleteAll),
        ),
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: Text(context.l10n.close),
        ),
      ],
    );
  }
}
