import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:verbnest_app/src/app.dart';
import 'package:verbnest_app/src/state/editor_state.dart';
import 'package:verbnest_app/src/state/session.dart';
import 'package:verbnest_core/verbnest_core.dart';
import 'package:verbnest_http/verbnest_http.dart';

class _Engine extends HttpEngine {
  @override
  Future<HttpResponseRecord> send(
    HttpRequestSpec spec, {
    CancelToken? cancel,
  }) async {
    final body = Uint8List.fromList(utf8.encode('{"ok": true}'));
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

/// A phone-size app with a request, an environment and a sent response.
Future<({ProviderContainer c, String col, String id})> _pump(
  WidgetTester t, {
  double textScale = 1,
  Size size = const Size(402, 874),
  bool dark = false,
}) async {
  t.view.physicalSize = size;
  t.view.devicePixelRatio = 1;
  t.platformDispatcher.textScaleFactorTestValue = textScale;
  addTearDown(t.view.reset);
  addTearDown(t.platformDispatcher.clearTextScaleFactorTestValue);
  final s = WorkspaceSession.memory();
  addTearDown(s.close);
  final col = s.repo.createCollection('Pet Store API');
  final id = s.repo.createRequest(
    col,
    HttpRequestItem(
      id: '',
      name: 'List pets',
      url: 'https://api.petstore.dev/v2/pets?limit=20',
    ),
  );
  s.repo.saveEnvironment(
    const Environment(
      id: 'env-dev',
      name: 'Development',
      variables: [Variable(key: 'baseUrl', value: 'https://api.petstore.dev')],
    ),
  );
  s.repo.settings = {...s.repo.settings, 'themeMode': dark ? 'dark' : 'light'};
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
  return (c: c, col: col, id: id);
}

Future<void> _openRequest(
  WidgetTester t,
  ({ProviderContainer c, String col, String id}) a,
) async {
  if (find.byKey(Key('node-${a.id}')).evaluate().isEmpty) {
    await t.tap(find.byKey(Key('node-${a.col}')));
    await t.pump(const Duration(milliseconds: 300));
  }
  await t.tap(find.byKey(Key('node-${a.id}')));
  await t.pump(const Duration(seconds: 1));
  await t.pump(const Duration(seconds: 1));
}

/// The screens a person uses, as steps that leave the app on that screen.
final _screens =
    <
      String,
      Future<void> Function(
        WidgetTester,
        ({ProviderContainer c, String col, String id}),
      )
    >{
      'collections': (t, a) async {},
      'request': (t, a) async => _openRequest(t, a),
      'response': (t, a) async {
        await _openRequest(t, a);
        await t.tap(find.byKey(const Key('send')));
        await t.pump(const Duration(seconds: 1));
        await t.pump(const Duration(seconds: 1));
      },
      'history': (t, a) async {
        await t.tap(find.text('History').last);
        await t.pump(const Duration(milliseconds: 400));
      },
      'environments': (t, a) async {
        await t.tap(find.text('Environments').last);
        await t.pump(const Duration(milliseconds: 400));
      },
      'settings': (t, a) async {
        await t.tap(find.text('Settings').last);
        await t.pump(const Duration(milliseconds: 400));
      },
    };

void main() {
  group('large text does not overflow', () {
    for (final scale in [2.0, 3.1]) {
      for (final e in _screens.entries) {
        testWidgets('${(scale * 100).round()}%: ${e.key}', (t) async {
          final a = await _pump(t, textScale: scale);
          await e.value(t, a);
          expect(t.takeException(), isNull);
          // Let autosave timers finish.
          await t.pump(EditorNotifier.saveDelay);
        });
      }
    }
  });

  group('accessibility guidelines on a phone', () {
    for (final e in _screens.entries) {
      testWidgets('${e.key}: tappable things have labels', (t) async {
        final h = t.ensureSemantics();
        final a = await _pump(t);
        await e.value(t, a);
        await expectLater(t, meetsGuideline(labeledTapTargetGuideline));
        await t.pump(EditorNotifier.saveDelay);
        h.dispose();
      });

      testWidgets('${e.key}: touch targets are 48 dp (Android)', (t) async {
        final h = t.ensureSemantics();
        final a = await _pump(t);
        await e.value(t, a);
        await expectLater(t, meetsGuideline(androidTapTargetGuideline));
        await t.pump(EditorNotifier.saveDelay);
        h.dispose();
      });

      testWidgets('${e.key}: touch targets are 44 dp (iOS)', (t) async {
        final h = t.ensureSemantics();
        final a = await _pump(t);
        await e.value(t, a);
        await expectLater(t, meetsGuideline(iOSTapTargetGuideline));
        await t.pump(EditorNotifier.saveDelay);
        h.dispose();
      });
    }
  });

  testWidgets('desktop: tappable things have labels', (t) async {
    final h = t.ensureSemantics();
    final a = await _pump(t, size: const Size(1280, 800));
    await _openRequest(t, a);
    await t.tap(find.byKey(const Key('send')));
    await t.pump(const Duration(seconds: 1));
    await expectLater(t, meetsGuideline(labeledTapTargetGuideline));
    await t.pump(EditorNotifier.saveDelay);
    h.dispose();
  });

  group('text contrast', () {
    for (final dark in [false, true]) {
      for (final e in _screens.entries) {
        testWidgets('${e.key}, ${dark ? 'dark' : 'light'}', (t) async {
          final h = t.ensureSemantics();
          final a = await _pump(t, dark: dark);
          await e.value(t, a);
          await expectLater(t, meetsGuideline(textContrastGuideline));
          await t.pump(EditorNotifier.saveDelay);
          h.dispose();
        });
      }
    }
  });
}
