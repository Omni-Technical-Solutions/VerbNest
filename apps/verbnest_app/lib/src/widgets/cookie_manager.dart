import 'package:material_ui/material_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:verbnest_core/verbnest_core.dart';

import '../state/network_state.dart';
import '../../l10n/l10n.dart';
import 'ui/still_tooltip.dart';

/// Lists the saved cookies by domain; remove one, a domain or all of them.
class CookieManagerDialog extends ConsumerWidget {
  const CookieManagerDialog({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final cookies = ref.watch(cookiesProvider);
    final n = ref.read(cookiesProvider.notifier);
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
            : _CookieList(cookies: cookies, notifier: n),
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

class _CookieList extends StatelessWidget {
  const _CookieList({required this.cookies, required this.notifier});

  final List<StoredCookie> cookies;
  final CookiesNotifier notifier;

  @override
  Widget build(BuildContext context) {
    final domains = <String>{for (final c in cookies) c.domain}.toList();
    return ListView(
      children: [
        for (final d in domains) ...[
          _domainHeader(context, d),
          for (final c in cookies.where((c) => c.domain == d))
            _cookieTile(context, c),
        ],
      ],
    );
  }

  Widget _domainHeader(BuildContext context, String d) {
    return ListTile(
      dense: true,
      title: Text(d, style: const TextStyle(fontWeight: FontWeight.w600)),
      trailing: StillIconButton(
        key: Key('clear-domain-$d'),
        tooltip: context.l10n.cookiesDeleteDomain(d),
        icon: const Icon(Icons.delete_sweep_outlined),
        onPressed: () => notifier.removeDomain(d),
      ),
    );
  }

  Widget _cookieTile(BuildContext context, StoredCookie c) {
    return ListTile(
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
              : context.l10n.cookieExpires('${c.expires!.toLocal()}'),
        ].join(' · '),
      ),
      trailing: StillIconButton(
        tooltip: context.l10n.delete,
        icon: const Icon(Icons.close),
        onPressed: () => notifier.remove(c),
      ),
    );
  }
}
