import 'package:flutter/material.dart';
import 'package:verbnest_core/verbnest_core.dart';

import '../../l10n/l10n.dart';

String _targetLabel(BuildContext context, AssertionTarget t) {
  final l = context.l10n;
  return switch (t) {
    AssertionTarget.status => l.asStatusCode,
    AssertionTarget.header => l.asHeader,
    AssertionTarget.jsonPath => l.asJsonPath,
    AssertionTarget.responseTime => l.asResponseTime,
    AssertionTarget.body => l.asBody,
    AssertionTarget.schema => l.asSchema,
  };
}

/// Builder for no-code response checks (FR-SCR-006). Results show in the
/// Tests tab next to `pm.test` results.
class AssertionsEditor extends StatelessWidget {
  const AssertionsEditor({
    super.key,
    required this.assertions,
    required this.onChanged,
  });

  final List<Assertion> assertions;
  final ValueChanged<List<Assertion>> onChanged;

  void _replace(int i, Assertion a) {
    final next = [...assertions];
    next[i] = a;
    onChanged(next);
  }

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.all(8),
      children: [
        for (var i = 0; i < assertions.length; i++)
          _row(context, i, assertions[i]),
        Align(
          alignment: AlignmentDirectional.centerStart,
          child: TextButton.icon(
            key: const Key('add-assertion'),
            onPressed: () => onChanged([
              ...assertions,
              const Assertion(target: AssertionTarget.status, value: '200'),
            ]),
            icon: const Icon(Icons.add),
            label: Text(context.l10n.asAdd),
          ),
        ),
      ],
    );
  }

  Widget _row(BuildContext context, int i, Assertion a) {
    final ops = Assertion.opsFor(a.target);
    final named =
        a.target == AssertionTarget.header ||
        a.target == AssertionTarget.jsonPath;
    final valueKey = ValueKey('v$i-${assertions.length}-${a.target.name}');
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Wrap(
        spacing: 8,
        runSpacing: 4,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          Checkbox(
            key: Key('assert-enabled-$i'),
            value: a.enabled,
            onChanged: (v) => _replace(i, a.copyWith(enabled: v ?? true)),
          ),
          DropdownButton<AssertionTarget>(
            key: Key('assert-target-$i'),
            value: a.target,
            items: [
              for (final t in AssertionTarget.values)
                DropdownMenuItem(
                  value: t,
                  child: Text(_targetLabel(context, t)),
                ),
            ],
            onChanged: (t) {
              if (t == null) return;
              final nextOps = Assertion.opsFor(t);
              _replace(
                i,
                Assertion(
                  target: t,
                  op: nextOps.contains(a.op) ? a.op : nextOps.first,
                  name: a.name,
                  value: a.value,
                  enabled: a.enabled,
                ),
              );
            },
          ),
          if (named)
            SizedBox(
              width: 180,
              child: TextFormField(
                key: ValueKey('n$i-${assertions.length}-${a.target.name}'),
                initialValue: a.name,
                decoration: InputDecoration(
                  isDense: true,
                  hintText: a.target == AssertionTarget.header
                      ? 'Content-Type'
                      : r'$.data[0].id',
                ),
                onChanged: (v) => _replace(i, a.copyWith(name: v)),
              ),
            ),
          if (a.target != AssertionTarget.schema)
            DropdownButton<AssertionOp>(
              key: Key('assert-op-$i'),
              value: ops.contains(a.op) ? a.op : ops.first,
              items: [
                for (final o in ops)
                  DropdownMenuItem(value: o, child: Text(o.label)),
              ],
              onChanged: (o) {
                if (o != null) _replace(i, a.copyWith(op: o));
              },
            ),
          if (a.op.needsValue || a.target == AssertionTarget.schema)
            SizedBox(
              width: a.target == AssertionTarget.schema ? 320 : 180,
              child: TextFormField(
                key: valueKey,
                initialValue: a.value,
                maxLines: a.target == AssertionTarget.schema ? 4 : 1,
                decoration: InputDecoration(
                  isDense: true,
                  hintText: a.target == AssertionTarget.schema
                      ? '{"type": "object", "required": ["id"]}'
                      : 'Expected value',
                ),
                onChanged: (v) => _replace(i, a.copyWith(value: v)),
              ),
            ),
          IconButton(
            key: Key('assert-delete-$i'),
            tooltip: context.l10n.remove,
            icon: const Icon(Icons.close, size: 18),
            onPressed: () => onChanged([
              for (var j = 0; j < assertions.length; j++)
                if (j != i) assertions[j],
            ]),
          ),
        ],
      ),
    );
  }
}
