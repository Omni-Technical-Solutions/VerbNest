import 'package:material_ui/material_ui.dart';

import '../ui/still_dropdown.dart';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:verbnest_core/verbnest_core.dart';

import '../../../l10n/l10n.dart';
import '../../state/editor_state.dart';
import '../../state/file_port.dart';
import '../../state/session.dart';
import '../graphql_editor.dart';
import '../kv_editor.dart';
import '../synced_field.dart';

class BodyTab extends ConsumerWidget {
  const BodyTab({super.key, required this.item, required this.notifier});

  final HttpRequestItem item;
  final EditorNotifier notifier;

  void _set(RequestBody b) => notifier.edit((i) => i.copyWith(body: b));

  /// Lets the user pick a file and stores it in the workspace.
  Future<({String id, String name})?> _store(WidgetRef ref) async {
    final f = await ref.read(filePortProvider).pick();
    if (f == null) return null;
    final name = safeFileName(f.name);
    final id = ref
        .read(repositoryProvider)
        .addAttachment(name, f.bytes, mime: f.mime);
    return (id: id, name: name);
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _BodyModePicker(body: item.body, notifier: notifier),
        Expanded(child: _content(context, ref, item.body)),
      ],
    );
  }

  Widget _content(BuildContext context, WidgetRef ref, RequestBody body) {
    return switch (body) {
      RawBody() => Padding(
        padding: const EdgeInsets.all(8),
        child: SyncedTextField(
          key: const Key('body-text'),
          value: body.text,
          variables: true,
          monospace: true,
          expands: true,
          onChanged: (v) => _set(RawBody(body.language, v)),
        ),
      ),
      GraphqlBody() => GraphqlEditor(
        body: body,
        url: item.url,
        notifier: notifier,
        onChanged: _set,
      ),
      UrlEncodedBody() => KeyValueEditor(
        idPrefix: 'urlencoded',
        rows: body.fields,
        onChanged: (f) => _set(UrlEncodedBody(f)),
      ),
      FormDataBody() => KeyValueEditor(
        idPrefix: 'form',
        allowBulk: false,
        onPickFile: (row) async {
          final stored = await _store(ref);
          if (stored == null) return null;
          return row.copyWith(
            type: KeyValueType.file,
            value: attachmentRef(stored.id, stored.name),
          );
        },
        rows: body.fields,
        onChanged: (f) => _set(FormDataBody(f)),
      ),
      BinaryBody() => _binary(context, ref, body),
      NoBody() => Center(child: Text(context.l10n.reNoBody)),
    };
  }

  Widget _binary(BuildContext context, WidgetRef ref, BinaryBody body) {
    final id = body.attachmentId;
    final info = id == null
        ? null
        : ref.read(repositoryProvider).attachment(id);
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            key: const Key('binary-info'),
            info == null
                ? context.l10n.reNoFile
                : context.l10n.reFileInfo(info.name, info.size),
          ),
          const SizedBox(height: 8),
          FilledButton.tonalIcon(
            key: const Key('binary-pick'),
            icon: const Icon(Icons.upload_file),
            label: Text(
              info == null
                  ? context.l10n.reChooseFile
                  : context.l10n.reReplaceFile,
            ),
            onPressed: () async {
              final stored = await _store(ref);
              if (stored != null) _set(BinaryBody(stored.id));
            },
          ),
          if (info != null)
            TextButton(
              key: const Key('binary-clear'),
              onPressed: () => _set(const BinaryBody(null)),
              child: Text(context.l10n.reRemoveFile),
            ),
        ],
      ),
    );
  }
}

class _BodyModePicker extends StatelessWidget {
  const _BodyModePicker({required this.body, required this.notifier});

  final RequestBody body;
  final EditorNotifier notifier;

  static const _modes = [
    'none',
    'json',
    'text',
    'xml',
    'html',
    'javascript',
    'graphql',
    'urlencoded',
    'form',
    'binary',
  ];

  static RequestBody _fresh(String mode) {
    for (final l in RawBodyLanguage.values) {
      if (l.name == mode) return RawBody(l, '');
    }
    return switch (mode) {
      'graphql' => const GraphqlBody(),
      'urlencoded' => const UrlEncodedBody([]),
      'form' => const FormDataBody([]),
      'binary' => const BinaryBody(null),
      _ => const NoBody(),
    };
  }

  void _onSelected(String? m) {
    if (m == null || m == body.mode) return;
    // A GraphQL operation is a POST; a GET with a body is rarely meant.
    notifier.edit(
      (i) => i.copyWith(
        body: _fresh(m),
        method: m == 'graphql' && i.method == 'GET' ? 'POST' : i.method,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12),
      child: StillDropdown<String>(
        key: const Key('body-mode'),
        value: _modes.contains(body.mode) ? body.mode : null,
        hintText: body.mode,
        expand: true,
        entries: [for (final m in _modes) StillEntry(value: m, label: m)],
        onSelected: _onSelected,
      ),
    );
  }
}
