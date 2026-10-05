import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'state/prefs.dart';
import 'state/session.dart';
import 'state/settings_state.dart';
import 'state/theme_state.dart';
import 'widgets/network_settings.dart';
import 'widgets/synced_field.dart';

/// Workspace HTTP defaults; requests can override them (FR-HTTP-007).
class SettingsPage extends ConsumerWidget {
  const SettingsPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = ref.watch(httpDefaultsProvider);
    final notifier = ref.read(httpDefaultsProvider.notifier);
    final protected = ref.watch(sessionProvider).secretsProtected;
    final prefs = ref.watch(prefsProvider);
    final prefsNotifier = ref.read(prefsProvider.notifier);
    return ListView(
      padding: const EdgeInsets.all(12),
      children: [
        ListTile(
          key: const Key('secrets-status'),
          leading: Icon(
            protected ? Icons.lock : Icons.warning_amber,
            color: protected ? null : Theme.of(context).colorScheme.error,
          ),
          title: Text(
            protected
                ? 'Secrets are kept in the system secret store'
                : 'Secrets are stored unencrypted on this device',
          ),
          subtitle: protected
              ? null
              : const Text(
                  'The system secret store is not available '
                  '(on Linux, install and unlock a keyring service).',
                ),
        ),
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
        const Divider(),
        const NetworkSettingsSection(),
        const Divider(),
        _section(context, 'Appearance (this device)'),
        ListTile(
          title: Text('Text size ${(prefs.fontScale * 100).round()}%'),
          subtitle: Slider(
            key: const Key('font-scale'),
            min: Prefs.minScale,
            max: Prefs.maxScale,
            divisions: 8,
            value: prefs.fontScale,
            onChanged: (v) =>
                prefsNotifier.update(prefs.copyWith(fontScale: v)),
          ),
        ),
        ListTile(
          title: Text('Code font size ${prefs.editorFontSize.round()}'),
          subtitle: Slider(
            key: const Key('editor-font-size'),
            min: Prefs.minEditorSize,
            max: Prefs.maxEditorSize,
            divisions: 14,
            value: prefs.editorFontSize,
            onChanged: (v) =>
                prefsNotifier.update(prefs.copyWith(editorFontSize: v)),
          ),
        ),
        const Divider(),
        _section(context, 'History (this device)'),
        SwitchListTile(
          key: const Key('history-bodies'),
          title: const Text('Keep request and response bodies'),
          subtitle: const Text('Off stores only URLs, headers and status'),
          value: prefs.historyBodies,
          onChanged: (v) =>
              prefsNotifier.update(prefs.copyWith(historyBodies: v)),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          child: SyncedTextField(
            key: const Key('history-days'),
            label: 'Delete history older than (days, 0 = never)',
            value: '${prefs.historyDays}',
            onChanged: (v) {
              final n = int.tryParse(v.trim());
              if (n != null && n >= 0) {
                prefsNotifier.update(prefs.copyWith(historyDays: n));
              }
            },
          ),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          child: SyncedTextField(
            key: const Key('history-max'),
            label: 'Keep at most this many entries',
            value: '${prefs.historyMax}',
            onChanged: (v) {
              final n = int.tryParse(v.trim());
              if (n != null && n > 0) {
                prefsNotifier.update(prefs.copyWith(historyMax: n));
              }
            },
          ),
        ),
      ],
    );
  }

  Widget _section(BuildContext context, String text) => Padding(
    padding: const EdgeInsetsDirectional.fromSTEB(16, 8, 16, 0),
    child: Text(text, style: Theme.of(context).textTheme.titleSmall),
  );
}
