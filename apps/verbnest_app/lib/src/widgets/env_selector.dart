import 'package:material_ui/material_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:verbnest_core/verbnest_core.dart';

import '../state/session.dart';
import '../state/variables.dart';
import '../../l10n/l10n.dart';

/// Environment dropdown plus a quick-look of the variables in effect
/// (FR-VAR-004).
class EnvSelector extends ConsumerWidget {
  const EnvSelector({super.key, this.requestId});

  /// When set, quick-look also shows that request's collection/folder scopes.
  final String? requestId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final envs = ref.watch(environmentsProvider);
    final active = ref.watch(activeEnvProvider);
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        DropdownMenu<String?>(
          key: const Key('env-select'),
          initialSelection: envs.any((e) => e.id == active) ? active : null,
          requestFocusOnTap: false,
          decorationBuilder: (_, _) =>
              InputDecoration(border: InputBorder.none, isDense: true),
          dropdownMenuEntries: [
            DropdownMenuEntry(value: null, label: context.l10n.noEnvironment),
            for (final e in envs) DropdownMenuEntry(value: e.id, label: e.name),
          ],
          onSelected: ref.read(activeEnvProvider.notifier).select,
        ),
        IconButton(
          key: const Key('quick-look'),
          tooltip: context.l10n.variablesInEffect,
          icon: const Icon(Icons.visibility_outlined),
          onPressed: () => showDialog<void>(
            context: context,
            builder: (_) => _QuickLook(requestId: requestId),
          ),
        ),
      ],
    );
  }
}

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
    return AlertDialog(
      title: Text(context.l10n.variablesInEffect),
      content: SizedBox(
        width: 420,
        child: vars.isEmpty
            ? Text(context.l10n.noVariablesDefined)
            : ListView(
                shrinkWrap: true,
                children: [
                  for (final r in vars)
                    ListTile(
                      dense: true,
                      title: Text(r.variable.key),
                      subtitle: Text(
                        r.variable.secret
                            ? VariableResolver.maskText
                            : r.variable.value,
                      ),
                      trailing: Text(r.scope.name),
                    ),
                ],
              ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: Text(context.l10n.close),
        ),
      ],
    );
  }
}
