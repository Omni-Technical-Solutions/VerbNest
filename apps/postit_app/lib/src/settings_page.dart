import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'state/settings_state.dart';
import 'state/theme_state.dart';
import 'widgets/synced_field.dart';

/// Workspace HTTP defaults; requests can override them (FR-HTTP-007).
class SettingsPage extends ConsumerWidget {
  const SettingsPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = ref.watch(httpDefaultsProvider);
    final notifier = ref.read(httpDefaultsProvider.notifier);
    return ListView(
      padding: const EdgeInsets.all(12),
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          child: SegmentedButton<ThemeMode>(
            key: const Key('theme-mode'),
            segments: const [
              ButtonSegment(value: ThemeMode.system, label: Text('System')),
              ButtonSegment(value: ThemeMode.light, label: Text('Light')),
              ButtonSegment(value: ThemeMode.dark, label: Text('Dark')),
            ],
            selected: {ref.watch(themeModeProvider)},
            onSelectionChanged: (s) =>
                ref.read(themeModeProvider.notifier).set(s.first),
          ),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          child: SyncedTextField(
            key: const Key('default-timeout'),
            label: 'Default timeout (seconds)',
            value: '${s.timeout.inSeconds}',
            onChanged: (v) {
              final secs = int.tryParse(v.trim());
              if (secs != null && secs > 0) {
                notifier.update(timeout: Duration(seconds: secs));
              }
            },
          ),
        ),
        SwitchListTile(
          key: const Key('default-verify-tls'),
          title: const Text('Verify TLS certificates'),
          subtitle: const Text('Turning this off is unsafe on public networks'),
          value: s.verifyTls,
          onChanged: (v) => notifier.update(verifyTls: v),
        ),
        SwitchListTile(
          key: const Key('warn-unresolved'),
          title: const Text('Warn before sending with undefined variables'),
          value: ref.watch(warnUnresolvedProvider),
          onChanged: ref.read(warnUnresolvedProvider.notifier).set,
        ),
        SwitchListTile(
          title: const Text('Follow redirects'),
          value: s.followRedirects,
          onChanged: (v) => notifier.update(followRedirects: v),
        ),
      ],
    );
  }
}
