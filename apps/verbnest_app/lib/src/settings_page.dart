import 'package:flutter/services.dart';
import 'package:material_ui/material_ui.dart';

import 'widgets/ui/still_controls.dart';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../l10n/l10n.dart';
import 'state/app_info_state.dart';
import 'state/prefs.dart';
import 'state/session.dart';
import 'state/settings_state.dart';
import 'state/theme_state.dart';
import 'theme.dart';
import 'widgets/network_settings.dart';
import 'widgets/synced_field.dart';
import 'widgets/ui/toast.dart';

/// Workspace HTTP defaults; requests can override them (FR-HTTP-007).
class SettingsPage extends ConsumerWidget {
  const SettingsPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final prefs = ref.watch(prefsProvider);
    final prefsNotifier = ref.read(prefsProvider.notifier);
    final version = ref.watch(appVersionProvider).asData?.value;
    return Align(
      alignment: Alignment.topCenter,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 760),
        child: ListView(
          padding: const EdgeInsets.all(Space.md),
          children: [
            _card([..._general(context, ref), ..._http(context, ref)]),
            _card([const NetworkSettingsSection()]),
            _card([
              _section(context, context.l10n.appearanceSection),
              ..._appearance(context, prefs, prefsNotifier),
            ]),
            _card([
              _section(context, context.l10n.historySection),
              StillSwitchListTile(
                key: const Key('scripts-trusted'),
                title: Text(context.l10n.trustScripts),
                subtitle: Text(context.l10n.trustScriptsHint),
                value: prefs.scriptsTrusted,
                onChanged: (v) =>
                    prefsNotifier.update(prefs.copyWith(scriptsTrusted: v)),
              ),
              ..._history(context, prefs, prefsNotifier),
            ]),
            _card([
              _section(context, context.l10n.aboutSection),
              ListTile(
                key: const Key('app-version'),
                leading: const Icon(Icons.info_outline),
                title: Text(context.l10n.aboutVersion),
                subtitle: Text(version?.label ?? ''),
                onTap: version == null
                    ? null
                    : () {
                        Clipboard.setData(
                          ClipboardData(text: 'VerbNest ${version.label}'),
                        );
                        showToast(
                          context,
                          context.l10n.aboutVersionCopied,
                          tone: ToastTone.success,
                        );
                      },
              ),
              ListTile(
                key: const Key('licenses'),
                leading: const Icon(Icons.balance_outlined),
                title: Text(context.l10n.aboutLicenses),
                subtitle: Text(context.l10n.aboutLicensesHint),
                trailing: const Icon(Icons.chevron_right),
                onTap: () => showLicensePage(
                  context: context,
                  applicationName: 'VerbNest',
                  applicationVersion: version?.label,
                  applicationLegalese: context.l10n.aboutLegalese,
                ),
              ),
            ]),
          ],
        ),
      ),
    );
  }

  Widget _card(List<Widget> children) => Card(
    margin: const EdgeInsets.only(bottom: Space.md),
    clipBehavior: Clip.antiAlias,
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: children,
    ),
  );

  List<Widget> _general(BuildContext context, WidgetRef ref) {
    final protected = ref.watch(sessionProvider).secretsProtected;
    return [
      ListTile(
        key: const Key('secrets-status'),
        leading: Icon(
          protected ? Icons.lock : Icons.warning_amber,
          color: protected ? null : Theme.of(context).colorScheme.error,
        ),
        title: Text(
          protected
              ? context.l10n.secretsProtected
              : context.l10n.secretsUnprotected,
        ),
        subtitle: protected ? null : Text(context.l10n.secretsUnavailableHint),
      ),
      Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        child: SegmentedButton<ThemeMode>(
          key: const Key('theme-mode'),
          segments: [
            ButtonSegment(
              value: ThemeMode.system,
              label: Text(context.l10n.themeSystem),
            ),
            ButtonSegment(
              value: ThemeMode.light,
              label: Text(context.l10n.themeLight),
            ),
            ButtonSegment(
              value: ThemeMode.dark,
              label: Text(context.l10n.themeDark),
            ),
          ],
          selected: {ref.watch(themeModeProvider)},
          onSelectionChanged: (s) =>
              ref.read(themeModeProvider.notifier).set(s.first),
        ),
      ),
    ];
  }

  List<Widget> _http(BuildContext context, WidgetRef ref) {
    final s = ref.watch(httpDefaultsProvider);
    final notifier = ref.read(httpDefaultsProvider.notifier);
    return [
      Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        child: SyncedTextField(
          key: const Key('default-timeout'),
          label: context.l10n.defaultTimeout,
          value: '${s.timeout.inSeconds}',
          onChanged: (v) {
            final secs = int.tryParse(v.trim());
            if (secs != null && secs > 0) {
              notifier.update(timeout: Duration(seconds: secs));
            }
          },
        ),
      ),
      StillSwitchListTile(
        key: const Key('default-verify-tls'),
        title: Text(context.l10n.verifyTls),
        subtitle: Text(context.l10n.verifyTlsHint),
        value: s.verifyTls,
        onChanged: (v) => notifier.update(verifyTls: v),
      ),
      StillSwitchListTile(
        key: const Key('warn-unresolved'),
        title: Text(context.l10n.warnUnresolved),
        value: ref.watch(warnUnresolvedProvider),
        onChanged: ref.read(warnUnresolvedProvider.notifier).set,
      ),
      StillSwitchListTile(
        title: Text(context.l10n.followRedirects),
        value: s.followRedirects,
        onChanged: (v) => notifier.update(followRedirects: v),
      ),
    ];
  }

  List<Widget> _appearance(
    BuildContext context,
    Prefs prefs,
    PrefsNotifier prefsNotifier,
  ) {
    final android = Theme.of(context).platform == TargetPlatform.android;
    return [
      // Material You exists on Android 12 and newer only.
      if (android)
        StillSwitchListTile(
          key: const Key('dynamic-color'),
          title: Text(context.l10n.settingsDynamicColor),
          subtitle: Text(context.l10n.settingsDynamicColorHint),
          value: prefs.dynamicColor,
          onChanged: (v) =>
              prefsNotifier.update(prefs.copyWith(dynamicColor: v)),
        ),
      ListTile(
        enabled: !(android && prefs.dynamicColor),
        title: Text(context.l10n.settingsAccent),
        subtitle: Padding(
          padding: const EdgeInsets.only(top: Space.sm),
          child: Wrap(
            key: const Key('accent-picker'),
            spacing: Space.sm,
            children: [
              for (var i = 0; i < AppAccents.seeds.length; i++)
                Semantics(
                  button: true,
                  selected: i == prefs.accent,
                  label: '${context.l10n.settingsAccent} ${i + 1}',
                  child: InkWell(
                    key: Key('accent-$i'),
                    customBorder: const CircleBorder(),
                    onTap: () =>
                        prefsNotifier.update(prefs.copyWith(accent: i)),
                    child: Container(
                      width: 28,
                      height: 28,
                      decoration: BoxDecoration(
                        color: AppAccents.seeds[i],
                        shape: BoxShape.circle,
                        border: Border.all(
                          width: 3,
                          color: i == prefs.accent
                              ? Theme.of(context).colorScheme.onSurface
                              : Colors.transparent,
                        ),
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
      StillSwitchListTile(
        key: const Key('compact-density'),
        title: Text(context.l10n.settingsCompact),
        subtitle: Text(context.l10n.settingsCompactHint),
        value: prefs.compact,
        onChanged: (v) => prefsNotifier.update(prefs.copyWith(compact: v)),
      ),
      ListTile(
        title: Text(
          context.l10n.settingsTextSize((prefs.fontScale * 100).round()),
        ),
        subtitle: StillSlider(
          key: const Key('font-scale'),
          min: Prefs.minScale,
          max: Prefs.maxScale,
          divisions: 8,
          value: prefs.fontScale,
          onChanged: (v) => prefsNotifier.update(prefs.copyWith(fontScale: v)),
        ),
      ),
      ListTile(
        title: Text(
          context.l10n.settingsCodeFontSize(prefs.editorFontSize.round()),
        ),
        subtitle: StillSlider(
          key: const Key('editor-font-size'),
          min: Prefs.minEditorSize,
          max: Prefs.maxEditorSize,
          divisions: 14,
          value: prefs.editorFontSize,
          onChanged: (v) =>
              prefsNotifier.update(prefs.copyWith(editorFontSize: v)),
        ),
      ),
    ];
  }

  List<Widget> _history(
    BuildContext context,
    Prefs prefs,
    PrefsNotifier prefsNotifier,
  ) {
    return [
      StillSwitchListTile(
        key: const Key('history-bodies'),
        title: Text(context.l10n.historyBodies),
        subtitle: Text(context.l10n.historyBodiesHint),
        value: prefs.historyBodies,
        onChanged: (v) =>
            prefsNotifier.update(prefs.copyWith(historyBodies: v)),
      ),
      Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        child: SyncedTextField(
          key: const Key('history-days'),
          label: context.l10n.historyDays,
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
          label: context.l10n.historyMax,
          value: '${prefs.historyMax}',
          onChanged: (v) {
            final n = int.tryParse(v.trim());
            if (n != null && n > 0) {
              prefsNotifier.update(prefs.copyWith(historyMax: n));
            }
          },
        ),
      ),
    ];
  }

  Widget _section(BuildContext context, String text) => Padding(
    padding: const EdgeInsetsDirectional.fromSTEB(16, 8, 16, 0),
    child: Text(text, style: Theme.of(context).textTheme.titleSmall),
  );
}
