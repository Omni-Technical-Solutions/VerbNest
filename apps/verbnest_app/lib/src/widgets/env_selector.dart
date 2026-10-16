import 'package:material_ui/material_ui.dart';

import 'ui/still_dropdown.dart';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:verbnest_core/verbnest_core.dart';

import '../state/session.dart';
import 'ui/adaptive_dialog.dart';
import '../state/variables.dart';
import '../../l10n/l10n.dart';
import 'ui/still_tooltip.dart';

/// Environment dropdown plus a quick-look of the variables in effect
/// (FR-VAR-004).
class EnvSelector extends ConsumerWidget {
  const EnvSelector({super.key, this.requestId, this.width});

  /// When set, quick-look also shows that request's collection/folder scopes.
  final String? requestId;

  /// A fixed width for the picker; by default it fits the row.
  final double? width;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final envs = ref.watch(environmentsProvider);
    final active = ref.watch(activeEnvProvider);
    return LayoutBuilder(
      builder: (context, c) => Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          StillDropdown<String?>(
            key: const Key('env-select'),
            // Fits the row; the eye button takes the other 48.
            width:
                width ??
                (c.maxWidth.isFinite
                    ? (c.maxWidth - 48).clamp(96.0, 220.0)
                    : null),
            value: envs.any((e) => e.id == active) ? active : null,
            bordered: false,
            entries: [
              StillEntry(value: null, label: context.l10n.noEnvironment),
              for (final e in envs) StillEntry(value: e.id, label: e.name),
            ],
            onSelected: ref.read(activeEnvProvider.notifier).select,
          ),
          StillIconButton(
            key: const Key('quick-look'),
            tooltip: context.l10n.variablesInEffect,
            icon: const Icon(Icons.visibility_outlined),
            // A bottom sheet on a phone, a dialog elsewhere.
            onPressed: () => showDetail(
              context,
              title: context.l10n.variablesInEffect,
              closeLabel: context.l10n.close,
              width: 420,
              content: _QuickLook(requestId: requestId),
            ),
          ),
        ],
      ),
    );
  }
}

/// The variables in effect for a request: name, value (masked for secrets)
/// and the scope each comes from. The caller supplies the title and frame.
class _QuickLook extends ConsumerWidget {
  const _QuickLook({this.requestId});

  final String? requestId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final session = ref.watch(sessionProvider);
    final scopes = buildScopes(
      session,
      requestId: requestId,
      envId: ref.watch(activeEnvProvider),
    );
    final vars = scopes.visible();
    if (vars.isEmpty) return Text(context.l10n.noVariablesDefined);
    return ListView(
      shrinkWrap: true,
      // The frame (sheet or dialog) does the scrolling.
      physics: const NeverScrollableScrollPhysics(),
      children: [
        for (final r in vars)
          ListTile(
            dense: true,
            title: Text(r.variable.key),
            subtitle: Text(
              r.variable.secret ? VariableResolver.maskText : r.variable.value,
            ),
            trailing: Text(r.scope.name),
          ),
      ],
    );
  }
}
