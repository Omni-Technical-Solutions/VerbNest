import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:verbnest_app/src/app.dart';
import 'package:verbnest_app/src/state/editor_state.dart';
import 'package:verbnest_app/src/state/session.dart';
import 'package:verbnest_app/src/state/tree_state.dart';
import 'package:verbnest_core/verbnest_core.dart';
import 'package:verbnest_http/verbnest_http.dart';

import 'device_profiles.dart';

/// Shared by the device matrix and the phone goldens: a seeded app on a fake
/// engine, opened the way a person would on each size.
class FakeEngine extends HttpEngine {
  FakeEngine({this.items = 2});

  /// How many objects the JSON response holds; more makes it scroll.
  final int items;

  @override
  Future<HttpResponseRecord> send(
    HttpRequestSpec spec, {
    CancelToken? cancel,
  }) async {
    final body = Uint8List.fromList(
      utf8.encode(
        jsonEncode([
          for (var i = 1; i <= items; i++)
            {'id': i, 'name': 'Pet $i', 'species': i.isEven ? 'cat' : 'dog'},
        ]),
      ),
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
        total: Duration(milliseconds: 40),
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

class MatrixApp {
  MatrixApp(this.t, this.c, this.col, this.id);
  final WidgetTester t;
  final ProviderContainer c;
  final String col, id;
}

Future<MatrixApp> launchApp(
  WidgetTester t,
  DeviceProfile p, {
  HttpEngine? engine,
}) async {
  t.view.physicalSize = p.size;
  t.view.devicePixelRatio = 1;
  addTearDown(t.view.reset);
  addTearDown(t.view.resetViewInsets);
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
  final c = ProviderContainer(
    overrides: [
      sessionProvider.overrideWithValue(s),
      engineProvider.overrideWithValue(engine ?? FakeEngine()),
    ],
  );
  addTearDown(c.dispose);
  await t.pumpWidget(
    UncontrolledProviderScope(container: c, child: const VerbnestApp()),
  );
  await t.pump(const Duration(milliseconds: 300));
  return MatrixApp(t, c, col, id);
}

/// Opens the request the way a person would on this size, then raises the
/// keyboard by focusing the URL field when the profile has one.
Future<void> openRequest(MatrixApp a, DeviceProfile p) async {
  final t = a.t;
  // List and detail share the screen only when it is wide and tall enough.
  if (p.size.width >= 840 && p.size.height >= 480) {
    a.c.read(tabsProvider.notifier).open(a.id);
  } else {
    if (find.byKey(Key('node-${a.id}')).evaluate().isEmpty) {
      await t.tap(find.byKey(Key('node-${a.col}')));
      await t.pump(const Duration(milliseconds: 300));
    }
    await t.tap(find.byKey(Key('node-${a.id}')));
  }
  await t.pump(const Duration(seconds: 1));
  await t.pump(const Duration(seconds: 1));
}

Future<void> raiseKeyboard(MatrixApp a, DeviceProfile p, Finder field) async {
  if (p.keyboard == 0) return;
  a.t.view.viewInsets = FakeViewPadding(bottom: p.keyboard);
  await a.t.tap(field);
  // One frame starts the toolbar's fold animation, the next lets it run.
  await a.t.pump(const Duration(milliseconds: 50));
  await a.t.pump(const Duration(milliseconds: 600));
}

/// Runs [body] and returns the layout errors Flutter reported, as text.
Future<List<String>> collectErrors(Future<void> Function() body) async {
  final errors = <String>[];
  final old = FlutterError.onError;
  FlutterError.onError = (d) =>
      errors.add(d.exceptionAsString().split('\n').first);
  try {
    await body();
  } finally {
    FlutterError.onError = old;
  }
  return errors;
}
