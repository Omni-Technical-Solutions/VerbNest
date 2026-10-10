import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/foundation.dart'
    show debugDefaultTargetPlatformOverride;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:verbnest_app/l10n/app_localizations.dart';
import 'package:verbnest_app/src/pages/environments_page.dart';
import 'package:verbnest_app/src/state/editor_state.dart';
import 'package:verbnest_app/src/state/session.dart';
import 'package:verbnest_app/src/widgets/request_editor.dart';
import 'package:verbnest_core/verbnest_core.dart';
import 'package:verbnest_http/verbnest_http.dart';

/// Phone widths that must not overflow: small Android, common Android, iPhone
/// 16 Pro, and the widest compact window.
const _widths = [320.0, 360.0, 402.0, 599.0];

class _Engine extends HttpEngine {
  @override
  Future<HttpResponseRecord> send(
    HttpRequestSpec spec, {
    CancelToken? cancel,
  }) async {
    final body = Uint8List.fromList(utf8.encode('{"ok":true}'));
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
        total: Duration(milliseconds: 12),
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

Future<String> _pump(
  WidgetTester t,
  double width, {
  required Widget Function(String id) body,
  TargetPlatform platform = TargetPlatform.android,
}) async {
  t.view.physicalSize = Size(width, 844);
  t.view.devicePixelRatio = 1;
  addTearDown(t.view.reset);
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
      variables: [
        Variable(key: 'baseUrl', value: 'https://api.petstore.dev/v2'),
        Variable(key: 'token', value: 'dev-token', secret: true),
      ],
    ),
  );
  await t.pumpWidget(
    ProviderScope(
      overrides: [
        sessionProvider.overrideWithValue(s),
        engineProvider.overrideWithValue(_Engine()),
      ],
      child: MaterialApp(
        theme: ThemeData(platform: platform),
        localizationsDelegates: [
          AppLocalizations.delegate,
          ...GlobalMaterialLocalizations.delegates,
        ],
        supportedLocales: AppLocalizations.supportedLocales,
        home: Scaffold(body: body(id)),
      ),
    ),
  );
  await t.pump(const Duration(milliseconds: 300));
  return id;
}

void main() {
  testWidgets('the selected request tab survives the first send', (t) async {
    await _pump(t, 402, body: (id) => RequestEditor(requestId: id));
    await t.tap(find.text('Auth'));
    await t.pump(const Duration(milliseconds: 300));
    final before = DefaultTabController.of(
      t.element(find.byType(TabBarView).first),
    ).index;
    expect(before, 2);
    await t.tap(find.byKey(const Key('send')));
    await t.pump(const Duration(milliseconds: 400));
    final after = DefaultTabController.of(
      t.element(find.byType(TabBarView).first),
    ).index;
    expect(after, 2);
  });

  for (final w in _widths) {
    testWidgets('request editor fits a ${w.toInt()} pt phone', (t) async {
      await _pump(t, w, body: (id) => RequestEditor(requestId: id));
      expect(t.takeException(), isNull);

      // The URL stays readable: room for about 20 characters.
      expect(t.getSize(find.byKey(const Key('url'))).width, greaterThan(110));
      if (w >= 402) {
        expect(t.getSize(find.byKey(const Key('url'))).width, greaterThan(180));
      }
      // The split toggle sat on top of the tab row and cannot work here.
      expect(find.byKey(const Key('split-orientation')), findsNothing);

      await t.tap(find.byKey(const Key('send')));
      await t.pump(const Duration(milliseconds: 400));
      expect(t.takeException(), isNull);
      // Response tabs keep their full labels reachable.
      expect(find.text('Cookies'), findsOneWidget);
    });

    testWidgets('environments fit a ${w.toInt()} pt phone', (t) async {
      await _pump(t, w, body: (_) => const EnvironmentsPage());
      await t.tap(find.text('Development'));
      await t.pump(const Duration(milliseconds: 300));
      expect(t.takeException(), isNull);
      // The name field is wide enough to read a variable name.
      expect(
        t.getSize(find.byKey(const ValueKey('var-key-0'))).width,
        greaterThan(110),
      );
    });
  }

  testWidgets('touch platforms show no keyboard hints', (t) async {
    await _pump(t, 402, body: (id) => RequestEditor(requestId: id));
    expect(find.text('Ctrl/Cmd + Enter'), findsNothing);
    expect(find.textContaining('Ctrl+'), findsNothing);
    expect(find.textContaining('⌘'), findsNothing);
  });

  testWidgets('desktop platforms keep the Send shortcut hint', (t) async {
    try {
      debugDefaultTargetPlatformOverride = TargetPlatform.macOS;
      await _pump(
        t,
        900,
        platform: TargetPlatform.macOS,
        body: (id) => RequestEditor(requestId: id),
      );
      expect(find.textContaining('⌘'), findsOneWidget);
    } finally {
      debugDefaultTargetPlatformOverride = null;
    }
  });
}
