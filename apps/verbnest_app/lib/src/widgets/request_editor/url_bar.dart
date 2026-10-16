import 'dart:convert';

import '../ui/still_dropdown.dart';

import 'dart:typed_data';

import 'package:material_ui/material_ui.dart';
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
  const UrlBar({
    super.key,
    required this.state,
    required this.notifier,
    this.compact = false,
    this.narrow = false,
    this.trailing,
  });

  final EditorState state;
  final EditorNotifier notifier;

  /// Phone width: a shorter method box and an icon-only Send button, so the
  /// URL keeps room to be read.
  final bool compact;

  /// Under 360 dp: an even narrower method box, to keep the URL readable.
  final bool narrow;

  /// Extra controls after Send, used in a short window where the toolbar is
  /// folded into this row.
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final item = state.item;
    // The tightest screens give up some padding for URL room.
    final gap = narrow ? 4.0 : 8.0;
    return Padding(
      padding: EdgeInsets.all(gap),
      child: Row(
        children: [
          _MethodDropdown(
            item: item,
            notifier: notifier,
            compact: compact,
            narrow: narrow,
          ),
          SizedBox(width: gap),
          Expanded(
            child: _UrlField(item: item, notifier: notifier),
          ),
          SizedBox(width: gap),
          if (!compact && trailing == null)
            LiveMenu(item: item, notifier: notifier),
          // Send and Cancel swap at once: a fade between them on every send
          // (and again when the response arrives) reads as flicker.
          KeyedSubtree(
            child: compact
                ? (state.sending
                      ? IconButton.filledTonal(
                          key: const Key('cancel'),
                          tooltip: context.l10n.reCancel,
                          onPressed: notifier.cancel,
                          icon: const Icon(Icons.stop),
                        )
                      : IconButton.filled(
                          key: const Key('send'),
                          tooltip: context.l10n.reSend,
                          onPressed: () {
                            lightHaptic(context);
                            notifier.send();
                          },
                          icon: const Icon(Icons.send),
                        ))
                : state.sending
                ? FilledButton.tonal(
                    key: const Key('cancel'),
                    onPressed: notifier.cancel,
                    child: Text(context.l10n.reCancel),
                  )
                : FilledButton(
                    key: const Key('send'),
                    onPressed: () {
                      lightHaptic(context);
                      notifier.send();
                    },
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(context.l10n.reSend),
                        if (showsKeyboardHints(context)) ...[
                          const SizedBox(width: Space.sm),
                          Kbd(
                            _sendHint(context),
                            color: Theme.of(context).colorScheme.onPrimary,
                          ),
                        ],
                      ],
                    ),
                  ),
          ),
          ?trailing,
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
  const _MethodDropdown({
    required this.item,
    required this.notifier,
    required this.compact,
    required this.narrow,
  });

  final HttpRequestItem item;
  final EditorNotifier notifier;
  final bool compact;
  final bool narrow;

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
    return StillDropdown<String>(
      key: const Key('method'),
      value: httpMethods.contains(item.method) ? item.method : null,
      width: narrow ? 108 : (compact ? 124 : 120),
      textStyle: TextStyle(
        fontWeight: FontWeight.bold,
        color: AppColors.of(context).method(item.method),
      ),
      bordered: false,
      hintText: item.method,
      // The default 16 px inset leaves no room for "DELETE" in a narrow box.
      contentPadding: compact
          ? const EdgeInsetsDirectional.only(start: 10)
          : null,
      entries: [
        for (final m in httpMethods) StillEntry(value: m, label: m),
        StillEntry(value: _customMethod, label: context.l10n.reCustom),
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

/// Opens a WebSocket, SSE or subscription session for the request.
void showLiveSession(
  BuildContext context,
  WidgetRef ref,
  EditorNotifier notifier,
  LiveKind kind,
) {
  showDialog<void>(
    animationStyle: AnimationStyle.noAnimation,
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

/// Menu that opens a WebSocket, SSE or subscription session for the request.
class LiveMenu extends ConsumerWidget {
  const LiveMenu({super.key, required this.item, required this.notifier});

  final HttpRequestItem item;
  final EditorNotifier notifier;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return PopupMenuButton<LiveKind>(
      popUpAnimationStyle: AnimationStyle.noAnimation,
      key: const Key('live'),
      tooltip: context.l10n.reLiveTooltip,
      icon: const Icon(Icons.sync_alt),
      onSelected: (kind) => showLiveSession(context, ref, notifier, kind),
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
