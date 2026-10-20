import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'ui/still_route.dart';

import 'package:material_ui/material_ui.dart';

import '../../l10n/l10n.dart';
import '../pages/console_page.dart';
import '../state/console_log.dart';
import '../state/editor_state.dart';
import '../state/network_state.dart';
import '../state/session.dart';
import '../state/settings_state.dart';
import '../state/tree_state.dart';
import '../state/variables.dart';
import '../theme.dart';
import 'cookie_manager.dart';
import 'ui/still_tooltip.dart';

/// Thin bar along the bottom of a desktop-size window: workspace, environment
/// in use, whether the open request is saved, and the network state that
/// changes what a send does (cookies, proxy, certificate checks), plus a
/// shortcut to the network console.
class StatusBar extends ConsumerWidget {
  const StatusBar({super.key});

  static const height = 28.0;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = context.l10n;
    final scheme = Theme.of(context).colorScheme;
    final colors = AppColors.of(context);
    final session = ref.watch(sessionProvider);
    ref.watch(workspaceVersionProvider);
    final envs = ref.watch(environmentsProvider);
    final activeEnv = ref.watch(activeEnvProvider);
    final envName = envs.where((e) => e.id == activeEnv).firstOrNull?.name;
    final activeTab = ref.watch(tabsProvider).active;
    final dirty =
        activeTab != null && ref.watch(editorProvider(activeTab)).dirty;
    final cookies = ref.watch(cookiesProvider).length;
    final net = ref.watch(networkProvider);
    final verifyTls = ref.watch(httpDefaultsProvider).verifyTls;
    final logCount = ref.watch(consoleLogProvider).length;

    // One item of the bar; the item's own look is in [_StatusItem].
    Widget item({
      Key? key,
      required IconData icon,
      required String label,
      Color? color,
      String? tooltip,
      VoidCallback? onTap,
    }) => _StatusItem(
      key: key,
      icon: icon,
      label: label,
      color: color,
      tooltip: tooltip,
      onTap: onTap,
    );

    return Material(
      key: const Key('status-bar'),
      color: scheme.surfaceContainer,
      child: SizedBox(
        height: height,
        child: Row(
          children: [
            const SizedBox(width: Space.sm),
            item(
              key: const Key('status-workspace'),
              icon: Icons.folder_outlined,
              label: session.repo.name,
            ),
            item(
              key: const Key('status-env'),
              icon: Icons.tune,
              label: envName ?? l.noEnvironment,
              tooltip: l.sbEnvTooltip,
            ),
            const Spacer(),
            if (!verifyTls)
              item(
                key: const Key('status-tls'),
                icon: Icons.lock_open,
                label: l.sbTlsOff,
                color: colors.warning,
              ),
            if (net.proxyEnabled)
              item(
                key: const Key('status-proxy'),
                icon: Icons.alt_route,
                label: l.sbProxyOn,
              ),
            _cookiesItem(context, cookies),
            _consoleItem(context, logCount),
            if (activeTab != null)
              item(
                key: const Key('status-save'),
                icon: dirty ? Icons.sync : Icons.check,
                label: dirty ? l.sbSaving : l.sbSaved,
              ),
            const SizedBox(width: Space.sm),
          ],
        ),
      ),
    );
  }
}

Widget _cookiesItem(BuildContext context, int count) {
  final l = context.l10n;
  return _StatusItem(
    key: const Key('status-cookies'),
    icon: Icons.cookie_outlined,
    label: l.nsCookies(count),
    tooltip: l.sbCookiesTooltip,
    onTap: () => showDialog<void>(
      animationStyle: AnimationStyle.noAnimation,
      context: context,
      builder: (_) => const CookieManagerDialog(),
    ),
  );
}

Widget _consoleItem(BuildContext context, int lines) {
  final l = context.l10n;
  return _StatusItem(
    key: const Key('status-console'),
    icon: Icons.terminal,
    label: lines == 0 ? l.sbConsole : '${l.sbConsole} $lines',
    tooltip: l.consoleTitle,
    onTap: () =>
        Navigator.of(context)
            .push(StillPageRoute<void>(builder: (_) => const ConsolePage())),
  );
}

class _StatusItem extends StatelessWidget {
  const _StatusItem({
    super.key,
    required this.icon,
    required this.label,
    this.color,
    this.tooltip,
    this.onTap,
  });

  final IconData icon;
  final String label;
  final Color? color;
  final String? tooltip;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final c = color ?? scheme.onSurfaceVariant;
    final style = Theme.of(context).textTheme.labelMedium?.copyWith(color: c);
    return StillTooltip(
      message: tooltip ?? label,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(Radii.sm),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: Space.sm),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 14, color: c),
              const SizedBox(width: Space.xs),
              Text(label, style: style),
            ],
          ),
        ),
      ),
    );
  }
}
