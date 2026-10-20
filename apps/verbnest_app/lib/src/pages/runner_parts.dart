import 'package:material_ui/material_ui.dart';
import 'package:verbnest_core/verbnest_core.dart';

import '../../l10n/l10n.dart';
import '../state/runner.dart';
import '../theme.dart';
import '../widgets/ui/ui.dart';

/// The ring and the stop button while a run is going.
class RunProgress extends StatelessWidget {
  const RunProgress({super.key, required this.run, required this.onStop});

  final RunnerState run;
  final VoidCallback onStop;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.all(8),
    child: Row(
      children: [
        SizedBox(
          width: 28,
          height: 28,
          child: Stack(
            alignment: Alignment.center,
            children: [
              CircularProgressIndicator(
                strokeWidth: 3,
                // Iterations advance in steps; between them the ring spins.
                value: run.total == 0 ? 0.0 : run.iteration / run.total,
              ),
              Text(
                run.total == 0
                    ? ''
                    : '${(100 * run.iteration / run.total).round()}',
                style: const TextStyle(fontSize: 8),
              ),
            ],
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Text(
            '${context.l10n.runProgress(run.iteration, run.total)}'
            '${run.currentName == null ? '' : ' · ${run.currentName}'}',
            key: const Key('run-progress'),
          ),
        ),
        OutlinedButton(
          key: const Key('run-stop'),
          onPressed: onStop,
          child: Text(context.l10n.runStop),
        ),
      ],
    ),
  );
}

/// The requests run so far, newest last, each expandable to its tests.
class RunResults extends StatelessWidget {
  const RunResults({super.key, required this.run});

  final RunnerState run;

  @override
  Widget build(BuildContext context) {
    if (run.entries.isEmpty) {
      return EmptyState(
        icon: Icons.play_circle_outline,
        title: context.l10n.runResultsHere,
      );
    }
    return ListView(
      key: const Key('run-results'),
      children: [for (final e in run.entries) _entryTile(context, run, e)],
    );
  }

  Widget _entryTile(BuildContext context, RunnerState run, RunEntry e) {
    final scheme = Theme.of(context).colorScheme;
    return ExpansionTile(
      expansionAnimationStyle: AnimationStyle.noAnimation,
      leading: Icon(
        e.skipped
            ? Icons.skip_next
            : e.ok
            ? Icons.check_circle
            : Icons.cancel,
        color: e.skipped
            ? null
            : e.ok
            ? AppColors.of(context).success
            : scheme.error,
      ),
      title: Text('${e.method} ${e.name}', overflow: TextOverflow.ellipsis),
      subtitle: Text(
        e.skipped
            ? context.l10n.runSkipped
            : context.l10n.runEntrySummary(
                    '${e.status ?? '—'}',
                    e.timeMs,
                    e.passedTests,
                    e.failedTests,
                  ) +
                  (run.total > 1
                      ? ' · ${context.l10n.runIterationSuffix(e.iteration)}'
                      : ''),
      ),
      children: [
        if (e.error != null)
          ListTile(
            dense: true,
            title: Text(e.error!, style: TextStyle(color: scheme.error)),
          ),
        for (final t in e.tests)
          ListTile(
            dense: true,
            leading: Icon(
              t.passed ? Icons.check : (t.failed ? Icons.close : Icons.remove),
              size: 16,
              color: t.failed ? scheme.error : null,
            ),
            title: Text(t.name),
            subtitle: t.message == null ? null : Text(t.message!),
          ),
      ],
    );
  }
}

/// The totals of a finished run and the buttons that export it.
class RunSummary extends StatelessWidget {
  const RunSummary({super.key, required this.report, required this.onExport});

  final RunReport report;
  final void Function(RunReport report, String kind) onExport;

  @override
  Widget build(BuildContext context) {
    final r = report;
    return Material(
      elevation: 2,
      child: Padding(
        padding: const EdgeInsets.all(8),
        child: Wrap(
          spacing: 8,
          runSpacing: 4,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            Text(
              context.l10n.runSummary(
                    r.requests,
                    r.passedTests,
                    r.failedTests,
                    r.errors,
                  ) +
                  (r.stoppedEarly ? ' · ${context.l10n.runStoppedEarly}' : ''),
              key: const Key('run-summary'),
            ),
            for (final (kind, label) in const [
              ('json', 'JSON'),
              ('junit', 'JUnit'),
              ('html', 'HTML'),
            ])
              OutlinedButton(
                key: Key('export-$kind'),
                onPressed: () => onExport(r, kind),
                child: Text(label),
              ),
          ],
        ),
      ),
    );
  }
}
