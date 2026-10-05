import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:postit_core/postit_core.dart';
import 'package:postit_storage/postit_storage.dart';

import '../state/session.dart';
import '../state/variables.dart';
import '../widgets/name_dialog.dart';

/// Environments and globals with their variables (FR-VAR-002..004).
class EnvironmentsPage extends ConsumerStatefulWidget {
  const EnvironmentsPage({super.key});

  @override
  ConsumerState<EnvironmentsPage> createState() => _EnvironmentsPageState();
}

class _EnvironmentsPageState extends ConsumerState<EnvironmentsPage> {
  /// null = globals.
  String? _selected;

  Future<void> _add() async {
    final name = await askName(
      context,
      title: 'New environment',
      action: 'Create',
    );
    if (name == null) return;
    final id = Ulid.generate();
    try {
      ref
          .read(repositoryProvider)
          .saveEnvironment(Environment(id: id, name: name));
      setState(() => _selected = id);
    } on DuplicateNameError {
      _toast('An environment named "$name" already exists');
    }
  }

  Future<void> _rename(Environment env) async {
    final name = await askName(context, title: 'Rename', initial: env.name);
    if (name == null) return;
    try {
      ref.read(repositoryProvider).saveEnvironment(env.copyWith(name: name));
    } on DuplicateNameError {
      _toast('An environment named "$name" already exists');
    }
  }

  Future<void> _delete(Environment env) async {
    final ok = await confirm(
      context,
      title: 'Delete "${env.name}"?',
      message: 'This cannot be undone.',
    );
    if (!ok) return;
    ref.read(repositoryProvider).deleteEnvironment(env.id);
    if (ref.read(activeEnvProvider) == env.id) {
      ref.read(activeEnvProvider.notifier).select(null);
    }
    setState(() => _selected = null);
  }

  void _toast(String text) =>
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));

  @override
  Widget build(BuildContext context) {
    final envs = ref.watch(environmentsProvider);
    final env = envs.where((e) => e.id == _selected).firstOrNull;
    final session = ref.watch(sessionProvider);
    final owner = env == null
        ? VariableOwner.global
        : VariableOwner.environment(env.id);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.all(8),
          child: Row(
            children: [
              Expanded(
                child: SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: Row(
                    children: [
                      ChoiceChip(
                        key: const Key('env-globals'),
                        label: const Text('Globals'),
                        selected: env == null,
                        onSelected: (_) => setState(() => _selected = null),
                      ),
                      for (final e in envs)
                        Padding(
                          padding: const EdgeInsetsDirectional.only(start: 8),
                          child: ChoiceChip(
                            key: Key('env-${e.id}'),
                            label: Text(e.name),
                            selected: e.id == env?.id,
                            onSelected: (_) => setState(() => _selected = e.id),
                          ),
                        ),
                    ],
                  ),
                ),
              ),
              IconButton(
                key: const Key('env-add'),
                tooltip: 'New environment',
                icon: const Icon(Icons.add),
                onPressed: _add,
              ),
              if (env != null) ...[
                IconButton(
                  tooltip: 'Rename',
                  icon: const Icon(Icons.edit_outlined),
                  onPressed: () => _rename(env),
                ),
                IconButton(
                  tooltip: 'Delete',
                  icon: const Icon(Icons.delete_outline),
                  onPressed: () => _delete(env),
                ),
              ],
            ],
          ),
        ),
        const Divider(height: 1),
        Expanded(
          child: VariablesEditor(
            key: ValueKey('${owner.kind}-${owner.id}'),
            initial: loadVariables(session, owner),
            initialCurrent: loadCurrentValues(session, owner),
            onChanged: (vars, cur) =>
                saveVariables(session, owner, vars, current: cur),
          ),
        ),
      ],
    );
  }
}

/// Table of variables: enabled, key, value, secret flag.
class VariablesEditor extends StatefulWidget {
  const VariablesEditor({
    super.key,
    required this.initial,
    required this.onChanged,
    this.initialCurrent = const {},
  });

  final List<Variable> initial;

  /// Device-local current values of plain variables, by name.
  final Map<String, String> initialCurrent;
  final void Function(List<Variable> vars, Map<String, String> current)
  onChanged;

  @override
  State<VariablesEditor> createState() => _VariablesEditorState();
}

class _VariablesEditorState extends State<VariablesEditor> {
  late List<Variable> _vars = [...widget.initial];
  late final Map<String, String> _current = {...widget.initialCurrent};
  final Set<int> _revealed = {};

  void _update(List<Variable> next) {
    setState(() => _vars = next);
    widget.onChanged(next, Map.of(_current));
  }

  void _setCurrent(String key, String value) {
    _current[key] = value;
    widget.onChanged(_vars, Map.of(_current));
  }

  List<String> get _duplicates {
    final seen = <String>{};
    return {
      for (final v in _vars)
        if (v.key.isNotEmpty && !seen.add(v.key)) v.key,
    }.toList();
  }

  void _set(int i, Variable v) => _update([..._vars]..[i] = v);

  Variable _copy(
    Variable v, {
    String? key,
    String? value,
    bool? secret,
    bool? enabled,
  }) => Variable(
    key: key ?? v.key,
    value: value ?? v.value,
    secret: secret ?? v.secret,
    enabled: enabled ?? v.enabled,
    description: v.description,
  );

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.all(8),
      children: [
        for (var i = 0; i < _vars.length; i++)
          Row(
            key: ValueKey('var-row-$i'),
            children: [
              Checkbox(
                value: _vars[i].enabled,
                onChanged: (v) => _set(i, _copy(_vars[i], enabled: v)),
              ),
              Expanded(
                child: TextFormField(
                  key: ValueKey('var-key-$i'),
                  initialValue: _vars[i].key,
                  decoration: const InputDecoration(
                    isDense: true,
                    hintText: 'Name',
                  ),
                  onChanged: (v) => _set(i, _copy(_vars[i], key: v)),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: TextFormField(
                  key: ValueKey(
                    'var-value-$i-${_vars[i].secret}${_revealed.contains(i) ? '-shown' : ''}',
                  ),
                  initialValue: _vars[i].value,
                  obscureText: _vars[i].secret && !_revealed.contains(i),
                  decoration: InputDecoration(
                    isDense: true,
                    hintText: _vars[i].secret
                        ? 'Secret value'
                        : 'Initial value',
                  ),
                  onChanged: (v) => _set(i, _copy(_vars[i], value: v)),
                ),
              ),
              if (_vars[i].secret)
                IconButton(
                  key: ValueKey('var-reveal-$i'),
                  tooltip: _revealed.contains(i) ? 'Hide' : 'Show',
                  icon: Icon(
                    _revealed.contains(i)
                        ? Icons.visibility_off
                        : Icons.visibility,
                    size: 18,
                  ),
                  onPressed: () => setState(() {
                    _revealed.contains(i)
                        ? _revealed.remove(i)
                        : _revealed.add(i);
                  }),
                )
              else ...[
                const SizedBox(width: 8),
                Expanded(
                  child: TextFormField(
                    key: ValueKey('var-current-$i-${_vars[i].key}'),
                    initialValue: _current[_vars[i].key] ?? '',
                    decoration: const InputDecoration(
                      isDense: true,
                      hintText: 'Current value (this device)',
                    ),
                    onChanged: (v) => _setCurrent(_vars[i].key, v),
                  ),
                ),
              ],
              IconButton(
                key: ValueKey('var-secret-$i'),
                tooltip: _vars[i].secret ? 'Secret' : 'Mark as secret',
                icon: Icon(
                  _vars[i].secret ? Icons.lock : Icons.lock_open,
                  size: 18,
                ),
                onPressed: () =>
                    _set(i, _copy(_vars[i], secret: !_vars[i].secret)),
              ),
              IconButton(
                tooltip: 'Remove',
                icon: const Icon(Icons.close, size: 18),
                onPressed: () => _update([..._vars]..removeAt(i)),
              ),
            ],
          ),
        if (_duplicates.isNotEmpty)
          Padding(
            padding: const EdgeInsets.all(8),
            child: Text(
              'Duplicate names: ${_duplicates.join(', ')}. The last one is used.',
              key: const Key('var-duplicates'),
              style: TextStyle(color: Theme.of(context).colorScheme.error),
            ),
          ),
        Align(
          alignment: AlignmentDirectional.centerStart,
          child: TextButton.icon(
            key: const Key('var-add'),
            icon: const Icon(Icons.add, size: 18),
            label: const Text('Add variable'),
            onPressed: () => _update([..._vars, const Variable(key: '')]),
          ),
        ),
      ],
    );
  }
}
