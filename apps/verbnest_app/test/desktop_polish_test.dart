import 'dart:convert';

import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:verbnest_app/src/app.dart';
import 'package:verbnest_app/src/state/editor_state.dart';
import 'package:verbnest_app/src/state/session.dart';
import 'package:verbnest_app/src/state/settings_state.dart';
import 'package:verbnest_app/src/state/tree_state.dart';
import 'package:verbnest_app/src/state/variables.dart';
import 'package:verbnest_core/verbnest_core.dart';
import 'package:verbnest_http/verbnest_http.dart';

class _Engine extends HttpEngine {
  @override
  Future<HttpResponseRecord> send(
    HttpRequestSpec spec, {
    CancelToken? cancel,
  }) async {
    final body = Uint8List.fromList(utf8.encode('{}'));
    const zero = Duration.zero;
    return HttpResponseRecord(
      status: 200,
      reason: 'OK',
      httpVersion: 'HTTP/1.1',
      headers: [('Content-Type', 'application/json')],
      body: body,
      wireBodySize: body.length,
      timings: const Timings(
        dns: zero,
        connect: zero,
        tls: zero,
        ttfb: zero,
        download: zero,
        total: zero,
      ),
      finalUrl: spec.url,
      sent: SentRequest(
        head: 'GET / HTTP/1.1\r\n',
        body: Uint8List(0),
        url: spec.url,
      ),
    );
  }
}

Future<({ProviderContainer c, List<String> ids})> _pump(
  WidgetTester t,
  Size size,
) async {
  t.view.physicalSize = size;
  t.view.devicePixelRatio = 1;
  addTearDown(t.view.reset);
  final s = WorkspaceSession.memory();
  addTearDown(s.close);
  s.repo.name = 'Pet Store';
  final col = s.repo.createCollection('C');
  final ids = [
    for (final n in ['A', 'B'])
      s.repo.createRequest(
        col,
        HttpRequestItem(id: '', name: n, url: 'https://x.dev/$n'),
      ),
  ];
  for (final (id, name) in [
    ('env-dev', 'Development'),
    ('env-prod', 'Production'),
  ]) {
    s.repo.saveEnvironment(
      Environment(id: id, name: name, variables: const []),
    );
  }
  final c = ProviderContainer(
    overrides: [
      sessionProvider.overrideWithValue(s),
      engineProvider.overrideWithValue(_Engine()),
    ],
  );
  addTearDown(c.dispose);
  await t.pumpWidget(
    UncontrolledProviderScope(container: c, child: const VerbnestApp()),
  );
  await t.pump(const Duration(milliseconds: 300));
  return (c: c, ids: ids);
}

Future<void> _chord(
  WidgetTester t,
  LogicalKeyboardKey key, {
  bool shift = false,
}) async {
  await t.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
  if (shift) await t.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
  await t.sendKeyEvent(key);
  if (shift) await t.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
  await t.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
  await t.pump(const Duration(milliseconds: 400));
}

void main() {
  group('status bar', () {
    testWidgets('shows on desktop widths, not on a phone or medium', (t) async {
      await _pump(t, const Size(1280, 800));
      expect(find.byKey(const Key('status-bar')), findsOneWidget);
      expect(find.text('Pet Store'), findsOneWidget);
      expect(find.byKey(const Key('status-console')), findsOneWidget);
    });

    testWidgets('hidden below the expanded size class', (t) async {
      await _pump(t, const Size(720, 900));
      expect(find.byKey(const Key('status-bar')), findsNothing);
      await _pump(t, const Size(402, 874));
      expect(find.byKey(const Key('status-bar')), findsNothing);
    });

    testWidgets('reports the environment, save state and risky settings', (
      t,
    ) async {
      final s = await _pump(t, const Size(1280, 800));
      expect(
        find.descendant(
          of: find.byKey(const Key('status-env')),
          matching: find.text('No environment'),
        ),
        findsOneWidget,
      );
      s.c.read(activeEnvProvider.notifier).select('env-prod');
      await t.pump(const Duration(milliseconds: 300));
      expect(
        find.descendant(
          of: find.byKey(const Key('status-env')),
          matching: find.text('Production'),
        ),
        findsOneWidget,
      );

      // No save state until a request is open; then it follows the edits.
      expect(find.byKey(const Key('status-save')), findsNothing);
      s.c.read(tabsProvider.notifier).open(s.ids[0]);
      await t.pump(const Duration(milliseconds: 300));
      expect(find.text('Saved'), findsOneWidget);

      expect(find.byKey(const Key('status-tls')), findsNothing);
      s.c.read(httpDefaultsProvider.notifier).update(verifyTls: false);
      await t.pump(const Duration(milliseconds: 300));
      expect(find.text('TLS checks off'), findsOneWidget);
    });
  });

  testWidgets('a keyboard-only pass: palette, environment, tabs, send', (
    t,
  ) async {
    final s = await _pump(t, const Size(1280, 800));
    s.c.read(tabsProvider.notifier)
      ..open(s.ids[0])
      ..open(s.ids[1]);
    await t.pump(const Duration(milliseconds: 300));
    expect(s.c.read(tabsProvider).active, s.ids[1]);

    // Change environment from the palette: Ctrl+K, type, Enter.
    await _chord(t, LogicalKeyboardKey.keyK);
    await t.enterText(find.byKey(const Key('palette-input')), 'Production');
    await t.pump(const Duration(milliseconds: 300));
    await t.testTextInput.receiveAction(TextInputAction.done);
    await t.pump(const Duration(milliseconds: 400));
    expect(s.c.read(activeEnvProvider), 'env-prod');

    // Switch tab: Ctrl+Tab wraps to the first.
    await t.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
    await t.sendKeyEvent(LogicalKeyboardKey.tab);
    await t.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
    await t.pump(const Duration(milliseconds: 300));
    expect(s.c.read(tabsProvider).active, s.ids[0]);

    // Send: Ctrl+Enter reaches the editor (it needs no mouse).
    await _chord(t, LogicalKeyboardKey.enter);
    await t.pump(const Duration(milliseconds: 500));
    expect(s.c.read(editorProvider(s.ids[0])).response?.status, 200);
    expect(t.takeException(), isNull);
    await t.pump(EditorNotifier.saveDelay);
  });
}
