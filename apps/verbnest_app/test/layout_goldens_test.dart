@Tags(['golden'])
library;

import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:verbnest_app/src/app.dart';
import 'package:verbnest_app/src/state/editor_state.dart';
import 'package:verbnest_app/src/state/session.dart';
import 'package:verbnest_app/src/state/tree_state.dart';
import 'package:verbnest_core/verbnest_core.dart';
import 'package:verbnest_http/verbnest_http.dart';

import 'support/golden_setup.dart';

/// The main workspace screen at a phone, tablet and desktop width, in both
/// themes. Regenerate with
/// `flutter test --update-goldens test/layout_goldens_test.dart` and look at
/// the images before committing them.
class _Engine extends HttpEngine {
  @override
  Future<HttpResponseRecord> send(
    HttpRequestSpec spec, {
    CancelToken? cancel,
  }) async {
    final body = Uint8List.fromList(
      utf8.encode('[{"id": 1, "name": "Biscuit"}, {"id": 2, "name": "Mochi"}]'),
    );
    const zero = Duration.zero;
    return HttpResponseRecord(
      status: 200,
      reason: 'OK',
      httpVersion: '1.1',
      headers: [('Content-Type', 'application/json')],
      body: body,
      wireBodySize: body.length,
      timings: const Timings(
        dns: zero,
        connect: zero,
        tls: zero,
        ttfb: zero,
        download: zero,
        total: Duration(milliseconds: 102),
      ),
      finalUrl: spec.url,
      sent: SentRequest(
        head: 'GET /pets HTTP/1.1\r\n',
        body: Uint8List(0),
        url: spec.url,
      ),
    );
  }
}

typedef _Case = ({String name, Size size});

const _cases = <_Case>[
  (name: 'compact', size: Size(402, 874)),
  (name: 'medium', size: Size(720, 900)),
  (name: 'expanded', size: Size(1280, 800)),
];

Future<void> _shot(
  WidgetTester t,
  _Case c, {
  required bool dark,
  required String file,
}) async {
  t.view.physicalSize = c.size;
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
      params: [KeyValue(key: 'limit', value: '20')],
    ),
  );
  s.repo.createRequest(
    col,
    HttpRequestItem(
      id: '',
      name: 'Create pet',
      method: 'POST',
      url: 'https://api.petstore.dev/v2/pets',
    ),
  );
  s.repo.saveEnvironment(
    const Environment(
      id: 'env-dev',
      name: 'Development',
      variables: [Variable(key: 'baseUrl', value: 'https://api.petstore.dev')],
    ),
  );
  s.repo.defaultEnvironmentId = 'env-dev';
  s.repo.settings = {...s.repo.settings, 'themeMode': dark ? 'dark' : 'light'};
  final container = ProviderContainer(
    overrides: [
      sessionProvider.overrideWithValue(s),
      engineProvider.overrideWithValue(_Engine()),
    ],
  );
  addTearDown(container.dispose);
  await t.pumpWidget(
    UncontrolledProviderScope(container: container, child: const VerbnestApp()),
  );
  await t.pump(const Duration(milliseconds: 300));

  if (c.size.width >= 1024) {
    container.read(tabsProvider.notifier).open(id);
  } else {
    // Phone and tablet open a request full screen from the collection list.
    if (find.byKey(Key('node-$id')).evaluate().isEmpty) {
      await t.tap(find.byKey(Key('node-$col')));
      await t.pump(const Duration(milliseconds: 300));
    }
    await t.tap(find.byKey(Key('node-$id')));
  }
  // The full-screen route needs a few frames to finish sliding in.
  await t.pump(const Duration(seconds: 1));
  await t.pump(const Duration(seconds: 1));
  await t.tap(find.byKey(const Key('send')));
  await t.pump(const Duration(seconds: 1));
  await t.pump(const Duration(seconds: 1));
  await expectLater(
    find.byType(MaterialApp),
    matchesGoldenFile('goldens/$file.png'),
  );
}

void main() {
  setUpAll(() async {
    await loadGoldenFonts();
    useTolerantGoldens('test/layout_goldens_test.dart');
  });

  for (final c in _cases) {
    for (final dark in [false, true]) {
      final theme = dark ? 'dark' : 'light';
      testWidgets('workspace, ${c.name}, $theme', (t) async {
        await _shot(t, c, dark: dark, file: 'layout-${c.name}-$theme');
      });
    }
  }
}
