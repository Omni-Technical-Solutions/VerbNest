import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:verbnest_app/src/state/console_log.dart';

ConsoleEntry entry(String text) => ConsoleEntry(
  at: DateTime(2026),
  method: 'HISTORY',
  url: '',
  sentHead: '',
  error: text,
);

void main() {
  test('a problem that repeats shows up once per session', () {
    final c = ProviderContainer();
    addTearDown(c.dispose);
    final log = c.read(consoleLogProvider.notifier);
    log.warnOnce('history', entry('first'));
    log.warnOnce('history', entry('second'));
    expect(c.read(consoleLogProvider).map((e) => e.error), ['first']);
    log.warnOnce('other', entry('third'));
    expect(c.read(consoleLogProvider), hasLength(2));
    // Clearing the console starts a new session of warnings.
    log.clear();
    log.warnOnce('history', entry('again'));
    expect(c.read(consoleLogProvider).map((e) => e.error), ['again']);
  });
}
