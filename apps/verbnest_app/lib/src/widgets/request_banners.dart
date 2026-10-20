import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

import '../../l10n/l10n.dart';
import '../state/editor_state.dart';
import '../state/settings_state.dart';
import 'ui/ui.dart';

/// Asks what to do about variables with no value before sending.
class PendingBanner extends ConsumerWidget {
  const PendingBanner({super.key, required this.state, required this.notifier});

  final EditorState state;
  final EditorNotifier notifier;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return InlineBanner(
      key: const Key('pending-banner'),
      tone: BannerTone.danger,
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

/// Asks whether a secret may be sent to a host it was not sent to before.
class SecretHostBanner extends StatelessWidget {
  const SecretHostBanner({
    super.key,
    required this.state,
    required this.notifier,
  });

  final EditorState state;
  final EditorNotifier notifier;

  @override
  Widget build(BuildContext context) {
    final pending = state.pendingSecretHost!;
    return InlineBanner(
      key: const Key('secret-host-banner'),
      tone: BannerTone.danger,
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

/// A warning from preparing the request.
class NoticeBanner extends StatelessWidget {
  const NoticeBanner(this.text, {super.key});

  final String text;

  @override
  Widget build(BuildContext context) {
    return InlineBanner(
      tone: BannerTone.warning,
      child: Text(text, key: const Key('banner')),
    );
  }
}
