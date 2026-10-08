import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:verbnest_core/verbnest_core.dart';

import '../../../l10n/l10n.dart';
import '../../state/editor_state.dart';
import '../../state/session.dart';
import '../../state/settings_state.dart';
import '../../state/var_text.dart';
import '../kv_editor.dart';

class HeadersTab extends ConsumerWidget {
  const HeadersTab({
    super.key,
    required this.item,
    required this.notifier,
    required this.requestId,
  });

  final HttpRequestItem item;
  final EditorNotifier notifier;
  final String requestId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final repo = ref.read(repositoryProvider);
    final defaults = ref.watch(httpDefaultsProvider);
    final auto = autoHeaders(
      item,
      effectiveAuth(item.auth, repo.authChain(requestId)),
      autoDecompress: item.settings.autoDecompress ?? defaults.autoDecompress,
    );
    return Column(
      children: [
        _AutoHeaders(auto: auto),
        Expanded(
          child: KeyValueEditor(
            idPrefix: 'headers',
            rows: item.headers,
            keySuggestions: headerNames,
            valueSuggestions: const {'content-type': contentTypes},
            onChanged: (h) => notifier.edit((i) => i.copyWith(headers: h)),
          ),
        ),
      ],
    );
  }
}

class _AutoHeaders extends StatelessWidget {
  const _AutoHeaders({required this.auto});

  final List<(String, String)> auto;

  @override
  Widget build(BuildContext context) {
    return ExpansionTile(
      key: const Key('auto-headers'),
      dense: true,
      title: Text(context.l10n.reGenerated(auto.length)),
      subtitle: Text(context.l10n.reGeneratedHint),
      children: [
        for (final h in auto)
          ListTile(
            dense: true,
            visualDensity: VisualDensity.compact,
            title: Text('${h.$1}: ${h.$2}'),
          ),
      ],
    );
  }
}
