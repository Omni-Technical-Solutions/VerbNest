import 'package:material_ui/material_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:verbnest_core/verbnest_core.dart';
import 'package:verbnest_storage/verbnest_storage.dart';

import '../state/session.dart';
import '../state/variables.dart';
import '../widgets/name_dialog.dart';
import '../../l10n/l10n.dart';
import '../widgets/ui/toast.dart';

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
      title: context.l10n.envNew,
      action: context.l10n.envCreate,
    );
    if (name == null || !mounted) return;
    final id = Ulid.generate();
    try {
      ref
          .read(repositoryProvider)
          .saveEnvironment(Environment(id: id, name: name));
      setState(() => _selected = id);
    } on DuplicateNameError {
      _toast(context.l10n.envExists(name));
    }
  }

  Future<void> _rename(Environment env) async {
    final name = await askName(
      context,
      title: context.l10n.rename,
      initial: env.name,
    );
    if (name == null || !mounted) return;
    try {
      ref.read(repositoryProvider).saveEnvironment(env.copyWith(name: name));
    } on DuplicateNameError {
      _toast(context.l10n.envExists(name));
    }
  }

  Future<void> _delete(Environment env) async {
    final ok = await confirm(
      context,
      title: context.l10n.envDeleteTitle(env.name),
      message: context.l10n.cannotUndo,
    );
    if (!ok) return;
    ref.read(repositoryProvider).deleteEnvironment(env.id);
    if (ref.read(activeEnvProvider) == env.id) {
      ref.read(activeEnvProvider.notifier).select(null);
    }
    setState(() => _selected = null);
  }

  void _toast(String text) => showToast(context, text);

  @override
  Widget build(BuildContext context) {
    final envs = ref.watch(environmentsProvider);
    final env = envs.where((e) => e.id == _selected).firstOrNull;
    final session = ref.watch(sessionProvider);
    final owner = env == null
        ? VariableOwner.global
        : VariableOwner.environment(env.id);

    return Align(
      alignment: Alignment.topCenter,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 960),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _toolbar(envs, env),
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
        ),
      ),
    );
  }

  Widget _toolbar(List<Environment> envs, Environment? env) {
    return Padding(
      padding: const EdgeInsets.all(8),
      child: Row(
        children: [
          Expanded(
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(children: _chips(envs, env)),
            ),
          ),
          IconButton(
            key: const Key('env-add'),
            tooltip: context.l10n.envNew,
            icon: const Icon(Icons.add),
            onPressed: _add,
          ),
          if (env != null) ...[
            IconButton(
              tooltip: context.l10n.rename,
              icon: const Icon(Icons.edit_outlined),
              onPressed: () => _rename(env),
            ),
            IconButton(
              tooltip: context.l10n.delete,
              icon: const Icon(Icons.delete_outline),
              onPressed: () => _delete(env),
            ),
          ],
        ],
      ),
    );
  }

  List<Widget> _chips(List<Environment> envs, Environment? env) {
    return [
      ChoiceChip(
        key: const Key('env-globals'),
        label: Text(context.l10n.envGlobals),
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
    ];
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
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 3),
            child: _row(context, i),
          ),
        if (_duplicates.isNotEmpty)
          Padding(
            padding: const EdgeInsets.all(8),
            child: Text(
              context.l10n.envDuplicates(_duplicates.join(', ')),
              key: const Key('var-duplicates'),
              style: TextStyle(color: Theme.of(context).colorScheme.error),
            ),
          ),
        Align(
          alignment: AlignmentDirectional.centerStart,
          child: TextButton.icon(
            key: const Key('var-add'),
            icon: const Icon(Icons.add, size: 18),
            label: Text(context.l10n.envAddVariable),
            onPressed: () => _update([..._vars, const Variable(key: '')]),
          ),
        ),
      ],
    );
  }

  Widget _row(BuildContext context, int i) {
    final v = _vars[i];
    return Row(
      key: ValueKey('var-row-$i'),
      children: [
        Checkbox(
          value: v.enabled,
          onChanged: (x) => _set(i, _copy(v, enabled: x)),
        ),
        Expanded(
          child: TextFormField(
            key: ValueKey('var-key-$i'),
            initialValue: v.key,
            decoration: InputDecoration(
              isDense: true,
              hintText: context.l10n.envVarName,
            ),
            onChanged: (x) => _set(i, _copy(v, key: x)),
          ),
        ),
        const SizedBox(width: 8),
        Expanded(child: _valueField(context, i)),
        if (v.secret)
          _revealButton(context, i)
        else ...[
          const SizedBox(width: 8),
          Expanded(child: _currentField(context, i)),
        ],
        IconButton(
          key: ValueKey('var-secret-$i'),
          tooltip: v.secret
              ? context.l10n.envSecret
              : context.l10n.envMarkSecret,
          icon: Icon(v.secret ? Icons.lock : Icons.lock_open, size: 18),
          onPressed: () => _set(i, _copy(v, secret: !v.secret)),
        ),
        IconButton(
          tooltip: context.l10n.remove,
          icon: const Icon(Icons.close, size: 18),
          onPressed: () => _update([..._vars]..removeAt(i)),
        ),
      ],
    );
  }

  Widget _valueField(BuildContext context, int i) {
    final v = _vars[i];
    return TextFormField(
      key: ValueKey(
        'var-value-$i-${v.secret}${_revealed.contains(i) ? '-shown' : ''}',
      ),
      initialValue: v.value,
      obscureText: v.secret && !_revealed.contains(i),
      decoration: InputDecoration(
        isDense: true,
        hintText: v.secret
            ? context.l10n.envSecretValue
            : context.l10n.envInitialValue,
      ),
      onChanged: (x) => _set(i, _copy(v, value: x)),
    );
  }

  Widget _revealButton(BuildContext context, int i) {
    final shown = _revealed.contains(i);
    return IconButton(
      key: ValueKey('var-reveal-$i'),
      tooltip: shown ? context.l10n.envHide : context.l10n.envShow,
      icon: Icon(shown ? Icons.visibility_off : Icons.visibility, size: 18),
      onPressed: () => setState(() {
        shown ? _revealed.remove(i) : _revealed.add(i);
      }),
    );
  }

  Widget _currentField(BuildContext context, int i) {
    final v = _vars[i];
    return TextFormField(
      key: ValueKey('var-current-$i-${v.key}'),
      initialValue: _current[v.key] ?? '',
      decoration: InputDecoration(
        isDense: true,
        hintText: context.l10n.envCurrentValue,
      ),
      onChanged: (x) => _setCurrent(v.key, x),
    );
  }
}
