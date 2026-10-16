import 'package:material_ui/material_ui.dart';

import '../ui/still_controls.dart';
import '../ui/still_dropdown.dart';

import 'package:verbnest_core/verbnest_core.dart';

import '../../../l10n/l10n.dart';
import '../../state/editor_state.dart';
import '../synced_field.dart';

class SettingsTab extends StatelessWidget {
  const SettingsTab({super.key, required this.item, required this.notifier});

  final HttpRequestItem item;
  final EditorNotifier notifier;

  void _set(RequestSettings s) => notifier.edit((i) => i.copyWith(settings: s));

  @override
  Widget build(BuildContext context) {
    final s = item.settings;
    return ListView(
      padding: const EdgeInsets.all(12),
      children: [
        _httpVersion(context, s),
        const SizedBox(height: 8),
        SyncedTextField(
          key: const Key('timeout'),
          label: context.l10n.reTimeout,
          value: s.timeoutMs?.toString() ?? '',
          onChanged: (v) => _set(s.copyWith(timeoutMs: int.tryParse(v.trim()))),
        ),
        const SizedBox(height: 8),
        SyncedTextField(
          key: const Key('max-redirects'),
          label: context.l10n.reMaxRedirects,
          value: s.maxRedirects?.toString() ?? '',
          onChanged: (v) =>
              _set(s.copyWith(maxRedirects: int.tryParse(v.trim()))),
        ),
        ..._redirectSwitches(context, s),
        ..._transportSwitches(context, s),
      ],
    );
  }

  Widget _httpVersion(BuildContext context, RequestSettings s) {
    return StillDropdown<String>(
      key: const Key('http-version'),
      value: s.httpVersion ?? 'auto',
      expand: true,
      labelText: context.l10n.reHttpVersion,
      helperText: context.l10n.reHttp2Hint,
      entries: [
        StillEntry(value: 'auto', label: context.l10n.reHttpAuto),
        StillEntry(value: '1.1', label: context.l10n.reHttp11),
        StillEntry(value: '2', label: context.l10n.reHttp2),
      ],
      onSelected: (v) => _set(s.copyWith(httpVersion: v == 'auto' ? null : v)),
    );
  }

  List<Widget> _redirectSwitches(BuildContext context, RequestSettings s) => [
    StillSwitchListTile(
      key: const Key('verify-tls'),
      title: Text(context.l10n.reVerifyTls),
      value: s.verifyTls ?? true,
      onChanged: (v) => _set(s.copyWith(verifyTls: v)),
    ),
    StillSwitchListTile(
      key: const Key('follow-redirects'),
      title: Text(context.l10n.reFollow),
      value: s.followRedirects ?? true,
      onChanged: (v) => _set(s.copyWith(followRedirects: v)),
    ),
    StillSwitchListTile(
      key: const Key('keep-method'),
      title: Text(context.l10n.reKeepMethod),
      value: s.keepMethodOnRedirect ?? false,
      onChanged: (v) => _set(s.copyWith(keepMethodOnRedirect: v)),
    ),
    StillSwitchListTile(
      key: const Key('strip-auth'),
      title: Text(context.l10n.reStripAuth),
      value: s.stripAuthCrossOrigin ?? true,
      onChanged: (v) => _set(s.copyWith(stripAuthCrossOrigin: v)),
    ),
  ];

  List<Widget> _transportSwitches(BuildContext context, RequestSettings s) => [
    StillSwitchListTile(
      key: const Key('send-cookies'),
      title: Text(context.l10n.reCookies),
      value: s.sendCookies ?? true,
      onChanged: (v) => _set(s.copyWith(sendCookies: v)),
    ),
    StillSwitchListTile(
      key: const Key('use-proxy'),
      title: Text(context.l10n.reUseProxy),
      subtitle: Text(context.l10n.reUseProxyHint),
      value: s.useProxy ?? true,
      onChanged: (v) => _set(s.copyWith(useProxy: v)),
    ),
    StillSwitchListTile(
      key: const Key('auto-decompress'),
      title: Text(context.l10n.reDecompress),
      value: s.autoDecompress ?? true,
      onChanged: (v) => _set(s.copyWith(autoDecompress: v)),
    ),
  ];
}
