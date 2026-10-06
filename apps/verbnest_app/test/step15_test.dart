import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:verbnest_app/src/pages/history_page.dart';
import 'package:verbnest_app/src/state/console_log.dart';
import 'package:verbnest_app/src/state/prefs.dart';
import 'package:verbnest_app/src/state/session.dart';
import 'package:verbnest_app/src/state/tree_state.dart';

ProviderContainer containerFor(WorkspaceSession s) {
  final c = ProviderContainer(
    overrides: [sessionProvider.overrideWithValue(s)],
  );
  addTearDown(c.dispose);
  return c;
}

void main() {
  test('prefs persist per device and clamp out-of-range values', () {
    final s = WorkspaceSession.memory();
    addTearDown(s.close);
    final a = containerFor(s);
    expect(a.read(prefsProvider).historyDays, 90);
    a
        .read(prefsProvider.notifier)
        .update(
          const Prefs(
            historyDays: 7,
            historyMax: 5,
            historyBodies: false,
            fontScale: 9,
            editorFontSize: 2,
          ),
        );
    final b = containerFor(s).read(prefsProvider);
    expect(b.historyDays, 7);
    expect(b.historyMax, 5);
    expect(b.historyBodies, isFalse);
    expect(b.fontScale, Prefs.maxScale);
    expect(b.editorFontSize, Prefs.minEditorSize);
  });

  test('dayLabel groups today, yesterday and older dates', () {
    final now = DateTime(2026, 3, 10, 12);
    expect(dayLabel(DateTime(2026, 3, 10, 1), now), 'Today');
    expect(dayLabel(DateTime(2026, 3, 9, 23), now), 'Yesterday');
    expect(dayLabel(DateTime(2026, 3, 1), now), '2026-03-01');
  });

  test('console keeps the newest 200 entries', () {
    final c = containerFor(WorkspaceSession.memory());
    ConsoleEntry e(int i) => ConsoleEntry(
      at: DateTime(2026),
      method: 'GET',
      url: 'u$i',
      sentHead: 'h',
    );
    for (var i = 0; i < ConsoleLog.capacity + 5; i++) {
      c.read(consoleLogProvider.notifier).add(e(i));
    }
    final log = c.read(consoleLogProvider);
    expect(log, hasLength(ConsoleLog.capacity));
    expect(log.first.url, 'u${ConsoleLog.capacity + 4}');
    c.read(consoleLogProvider.notifier).clear();
    expect(c.read(consoleLogProvider), isEmpty);
  });

  test('open tabs survive a restart and skip deleted requests', () {
    final s = WorkspaceSession.memory();
    addTearDown(s.close);
    final a = containerFor(s);
    final actions = a.read(treeActionsProvider);
    final col = actions.newCollection('C');
    final r1 = actions.newRequest(col, name: 'one');
    final r2 = actions.newRequest(col, name: 'two');
    final r3 = actions.newRequest(col, name: 'three');
    a.read(tabsProvider.notifier).activate(r2);
    s.repo.delete(r3);

    final b = containerFor(s).read(tabsProvider);
    expect(b.open, [r1, r2]);
    expect(b.active, r2);
  });

  test('tab stepping wraps in both directions', () {
    final s = WorkspaceSession.memory();
    addTearDown(s.close);
    final c = containerFor(s);
    final actions = c.read(treeActionsProvider);
    final col = actions.newCollection('C');
    final r1 = actions.newRequest(col);
    final r2 = actions.newRequest(col);
    final tabs = c.read(tabsProvider.notifier);
    expect(c.read(tabsProvider).active, r2);
    tabs.step(1);
    expect(c.read(tabsProvider).active, r1);
    tabs.step(-1);
    expect(c.read(tabsProvider).active, r2);
  });
}
