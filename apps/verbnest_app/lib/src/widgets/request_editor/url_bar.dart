import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:verbnest_core/verbnest_core.dart';
import 'package:verbnest_import/verbnest_import.dart';

import '../../../l10n/l10n.dart';
import '../../state/editor_state.dart';
import '../../state/file_port.dart';
import '../../theme.dart';
import '../name_dialog.dart';
import '../realtime_dialog.dart';
import '../synced_field.dart';
import '../ui/ui.dart';

const _customMethod = '\u0000custom';

const httpMethods = [
  'GET',
  'POST',
  'PUT',
  'PATCH',
  'DELETE',
  'HEAD',
  'OPTIONS',
];

class UrlBar extends StatelessWidget {
  const UrlBar({super.key, required this.state, required this.notifier});

  final EditorState state;
  final EditorNotifier notifier;

  @override
  Widget build(BuildContext context) {
    final item = state.item;
    return Padding(
      padding: const EdgeInsets.all(8),
      child: Row(
        children: [
          _MethodDropdown(item: item, notifier: notifier),
          const SizedBox(width: 8),
          Expanded(
            child: _UrlField(item: item, notifier: notifier),
          ),
          const SizedBox(width: 8),
          _LiveMenu(item: item, notifier: notifier),
          AnimatedSwitcher(
            duration: Motion.of(context, Motion.fast),
            transitionBuilder: (child, anim) => FadeTransition(
              opacity: anim,
              child: ScaleTransition(
                scale: Tween(begin: 0.92, end: 1.0).animate(anim),
                child: child,
              ),
            ),
            child: state.sending
                ? FilledButton.tonal(
                    key: const Key('cancel'),
                    onPressed: notifier.cancel,
                    child: Text(context.l10n.reCancel),
                  )
                : FilledButton(
                    key: const Key('send'),
                    onPressed: notifier.send,
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(context.l10n.reSend),
                        const SizedBox(width: Space.sm),
                        Kbd(
                          _sendHint(context),
                          color: Theme.of(context).colorScheme.onPrimary,
                        ),
                      ],
                    ),
                  ),
          ),
        ],
      ),
    );
  }
}

String _sendHint(BuildContext context) => switch (Theme.of(context).platform) {
  TargetPlatform.macOS || TargetPlatform.iOS => '⌘↵',
  _ => 'Ctrl+↵',
};

class _MethodDropdown extends StatelessWidget {
  const _MethodDropdown({required this.item, required this.notifier});

  final HttpRequestItem item;
  final EditorNotifier notifier;

  Future<void> _onSelected(BuildContext context, String? m) async {
    if (m == null) return;
    if (m != _customMethod) {
      notifier.edit((i) => i.copyWith(method: m));
      return;
    }
    final custom = await askName(
      context,
      title: context.l10n.reCustomMethod,
      initial: httpMethods.contains(item.method) ? '' : item.method,
      action: context.l10n.reSet,
    );
    if (custom != null) {
      notifier.edit((i) => i.copyWith(method: custom.trim().toUpperCase()));
    }
  }

  @override
  Widget build(BuildContext context) {
    return DropdownMenu<String>(
      key: const Key('method'),
      initialSelection: httpMethods.contains(item.method) ? item.method : null,
      width: 120,
      textStyle: TextStyle(
        fontWeight: FontWeight.bold,
        color: AppColors.of(context).method(item.method),
      ),
      requestFocusOnTap: false,
      decorationBuilder: (_, _) => InputDecoration(
        border: InputBorder.none,
        isDense: true,
        hintText: item.method,
      ),
      dropdownMenuEntries: [
        for (final m in httpMethods) DropdownMenuEntry(value: m, label: m),
        DropdownMenuEntry(value: _customMethod, label: context.l10n.reCustom),
      ],
      onSelected: (m) => _onSelected(context, m),
    );
  }
}

class _UrlField extends StatelessWidget {
  const _UrlField({required this.item, required this.notifier});

  final HttpRequestItem item;
  final EditorNotifier notifier;

  /// URL edited: refresh the params table from the query and the path
  /// variable rows from `/:name` segments, keeping disabled rows and values.
  static HttpRequestItem _withUrl(HttpRequestItem i, String url) {
    final fromUrl = UrlText.params(url);
    final disabled = i.params.where((p) => !p.enabled);
    final oldVars = {for (final v in i.pathVars) v.key: v};
    return i.copyWith(
      url: url,
      params: [...fromUrl, ...disabled],
      pathVars: [
        for (final n in UrlText.pathVariables(url))
          oldVars[n] ?? KeyValue(key: n),
      ],
    );
  }

  void _onChanged(String u) {
    if (looksLikeCurl(u)) {
      try {
        final c = parseCurl(u).item;
        notifier.edit(
          (i) => i.copyWith(
            method: c.method,
            url: c.url,
            params: c.params,
            headers: c.headers,
            body: c.body,
            auth: c.auth,
            settings: c.settings,
          ),
        );
        return;
      } on FormatException {
        // Still typing; keep the text as a plain URL.
      }
    }
    notifier.edit((i) => _withUrl(i, u));
  }

  @override
  Widget build(BuildContext context) {
    return SyncedTextField(
      key: const Key('url'),
      value: item.url,
      hint: 'https://example.com/path?query={{var}}',
      variables: true,
      onChanged: _onChanged,
    );
  }
}

class _LiveMenu extends ConsumerWidget {
  const _LiveMenu({required this.item, required this.notifier});

  final HttpRequestItem item;
  final EditorNotifier notifier;

  void _open(BuildContext context, WidgetRef ref, LiveKind kind) {
    showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (_) => RealtimeDialog(
        sse: kind != LiveKind.websocket,
        title: switch (kind) {
          LiveKind.websocket => context.l10n.reLiveWs,
          LiveKind.sse => context.l10n.reLiveSseTitle,
          LiveKind.graphqlSubscription => context.l10n.reLiveSub,
        },
        connect: () => notifier.connectRealtime(kind),
        onSave: (text) async {
          final port = ref.read(filePortProvider);
          await port.save(
            'live-log.txt',
            Uint8List.fromList(utf8.encode(text)),
            mime: 'text/plain',
          );
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return PopupMenuButton<LiveKind>(
      key: const Key('live'),
      tooltip: context.l10n.reLiveTooltip,
      icon: const Icon(Icons.sync_alt),
      onSelected: (kind) => _open(context, ref, kind),
      itemBuilder: (_) => [
        PopupMenuItem(
          value: LiveKind.websocket,
          child: Text(context.l10n.reLiveWs),
        ),
        PopupMenuItem(value: LiveKind.sse, child: Text(context.l10n.reLiveSse)),
        if (item.body is GraphqlBody)
          PopupMenuItem(
            value: LiveKind.graphqlSubscription,
            child: Text(context.l10n.reLiveSub),
          ),
      ],
    );
  }
}
