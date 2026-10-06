import 'package:flutter/material.dart';
import 'package:verbnest_core/verbnest_core.dart';

import 'synced_field.dart';
import '../../l10n/l10n.dart';

/// Pre-request and post-response script boxes (FR-SCR-001). Highlights
/// JavaScript and completes `pm.` members.
class ScriptsEditor extends StatefulWidget {
  const ScriptsEditor({
    super.key,
    required this.scripts,
    required this.onChanged,
    this.idPrefix = 'script',
    this.fontSize,
  });

  final Scripts scripts;
  final ValueChanged<Scripts> onChanged;
  final String idPrefix;
  final double? fontSize;

  @override
  State<ScriptsEditor> createState() => _ScriptsEditorState();
}

class _ScriptsEditorState extends State<ScriptsEditor> {
  late Scripts _scripts = widget.scripts;
  bool _post = false;

  void _set(Scripts next) {
    _scripts = next;
    widget.onChanged(next);
  }

  @override
  Widget build(BuildContext context) {
    final p = widget.idPrefix;
    return Padding(
      padding: const EdgeInsets.all(8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              SegmentedButton<bool>(
                key: Key('$p-phase'),
                showSelectedIcon: false,
                segments: [
                  ButtonSegment(
                    value: false,
                    label: Text(
                      _scripts.pre.isEmpty
                          ? context.l10n.scriptPre
                          : context.l10n.scriptPreSet,
                    ),
                  ),
                  ButtonSegment(
                    value: true,
                    label: Text(
                      _scripts.post.isEmpty
                          ? context.l10n.scriptPost
                          : context.l10n.scriptPostSet,
                    ),
                  ),
                ],
                selected: {_post},
                onSelectionChanged: (s) => setState(() => _post = s.first),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Expanded(
            child: _post
                ? SyncedTextField(
                    key: Key('$p-post'),
                    value: _scripts.post,
                    hint: "pm.test('Status is 200', () => {\n  pm.response.to.have.status(200);\n});",
                    monospace: true,
                    script: true,
                    expands: true,
                    fontSize: widget.fontSize,
                    onChanged: (v) => _set(Scripts(pre: _scripts.pre, post: v)),
                  )
                : SyncedTextField(
                    key: Key('$p-pre'),
                    value: _scripts.pre,
                    hint: "pm.environment.set('token', 'abc');",
                    monospace: true,
                    script: true,
                    expands: true,
                    fontSize: widget.fontSize,
                    onChanged: (v) =>
                        _set(Scripts(pre: v, post: _scripts.post)),
                  ),
          ),
          const SizedBox(height: 4),
          Text(
            context.l10n.scriptHelp,
            style: Theme.of(context).textTheme.bodySmall,
          ),
        ],
      ),
    );
  }
}
