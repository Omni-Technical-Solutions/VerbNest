// Renders the app screens to PNG files for the store listings.
//
// Run through scripts/screenshots_macos.sh. It does nothing unless
// VERBNEST_SHOTS_DIR is set, so a plain `flutter test` skips it.
//
// The app runs headless inside flutter_test: no window, no screen-recording
// permission, and the same pixels on every run. Responses come from a canned
// engine, so no network is used. Text uses Roboto from the Flutter SDK and the
// macOS monospace font, loaded below, because the test environment has no
// fonts of its own.
import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart'
    show debugDefaultTargetPlatformOverride;
import 'package:material_ui/material_ui.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:verbnest_app/src/app.dart';
import 'package:verbnest_app/src/scripting/script_engine.dart';
import 'package:verbnest_app/src/scripting/script_io.dart';
import 'package:verbnest_app/src/workspace_host.dart';
import 'package:verbnest_app/src/state/session.dart';
import 'package:verbnest_app/src/state/editor_state.dart';
import 'package:verbnest_core/verbnest_core.dart';
import 'package:verbnest_http/verbnest_http.dart';
import 'package:verbnest_storage/verbnest_storage.dart';

/// One output size per store listing. Pixel sizes match the Triplogger
/// listings so both apps share the same store assets: iPhone 6.3" (Dynamic
/// Island, 402 x 874 pt) and iPad
/// 13" for the App Store, phone and 10" tablet for Google Play, and 2880 x
/// 1800 (16:10) for the Mac App Store.
class _Profile {
  const _Profile(this.pixels, this.ratio, this.platform, {this.only});

  final Size pixels;
  final double ratio;
  final TargetPlatform platform;

  /// Screens to keep; null keeps every screen the profile can show.
  final Set<String>? only;

  Size get logical => Size(pixels.width / ratio, pixels.height / ratio);
  bool get phone => logical.width < 600;
}

const _tabletShots = {
  '01-request-and-response',
  '02-create-pet-body',
  '03-auth-inherited-bearer',
  '05-assertions-and-test-results',
  '06-response-headers',
  '07-command-palette',
  '14-history',
  '16-environments',
  '17-settings',
  '18-dark-theme',
};

const _profiles = {
  // iOS typography stands in for macOS: the test engine ignores fonts
  // registered under macOS's dot-prefixed family, and both use San Francisco
  // with ⌘ shortcuts.
  'macos': _Profile(Size(2880, 1800), 2, TargetPlatform.iOS),
  'iphone': _Profile(Size(1206, 2622), 3, TargetPlatform.iOS),
  'ipad': _Profile(Size(2064, 2752), 2, TargetPlatform.iOS, only: _tabletShots),
  'android-phone': _Profile(Size(1080, 2424), 3, TargetPlatform.android),
  'android-tablet': _Profile(
    Size(2560, 1600),
    2,
    TargetPlatform.android,
    only: _tabletShots,
  ),
};

final _profile =
    _profiles[Platform.environment['VERBNEST_SHOTS_PROFILE'] ?? 'macos'] ??
    (throw ArgumentError('Unknown VERBNEST_SHOTS_PROFILE'));
final _logical = _profile.logical;
final _ratio = _profile.ratio;

final _out = Platform.environment['VERBNEST_SHOTS_DIR'];
final _boundary = GlobalKey();

/// The real script engine needs the native library, which flutter_test does
/// not load, so scripts report the results the demo scripts would give.
class _ShotScripts implements ScriptEngine {
  @override
  Future<ScriptOutput> run(
    ScriptInput input, {
    Duration timeout = defaultScriptTimeout,
  }) async {
    if (input.phase == ScriptPhase.pre) return const ScriptOutput();
    return const ScriptOutput(
      tests: [
        TestResult(name: 'Pet was created', status: 'pass'),
        TestResult(name: 'Name matches the request', status: 'pass'),
      ],
      logs: [ConsoleLine('log', 'Saved petId to the environment')],
    );
  }
}

class _ShotEngine extends HttpEngine {
  @override
  Future<HttpResponseRecord> send(
    HttpRequestSpec spec, {
    CancelToken? cancel,
  }) async {
    final path = spec.url.path.replaceFirst(RegExp(r'^/v2'), '');
    final (status, reason, body) = switch ((spec.method, path)) {
      ('GET', '/pets') => (200, 'OK', _pets),
      ('GET', _) when path.startsWith('/pets/') => (200, 'OK', _pet),
      ('POST', '/pets') => (201, 'Created', _created),
      ('DELETE', _) => (204, 'No Content', ''),
      _ => (200, 'OK', '{"ok":true}'),
    };
    final bytes = Uint8List.fromList(utf8.encode(body));
    return HttpResponseRecord(
      status: status,
      reason: reason,
      httpVersion: 'HTTP/1.1',
      headers: [
        if (bytes.isNotEmpty) ('Content-Type', 'application/json'),
        ('Content-Length', '${bytes.length}'),
        ('Cache-Control', 'no-store'),
        ('Date', 'Mon, 05 Oct 2026 04:20:00 GMT'),
        ('Server', 'petstore/2.4'),
        ('X-Request-Id', 'a1f4c2d0-77b3-4e1f-9d2c-5b8e60a1f3c9'),
      ],
      body: bytes,
      wireBodySize: bytes.length,
      timings: const Timings(
        dns: Duration(milliseconds: 4),
        connect: Duration(milliseconds: 11),
        tls: Duration(milliseconds: 23),
        ttfb: Duration(milliseconds: 58),
        download: Duration(milliseconds: 6),
        total: Duration(milliseconds: 102),
      ),
      finalUrl: spec.url,
      sent: SentRequest(
        head:
            '${spec.method} ${spec.url.path} HTTP/1.1\r\n'
            'Host: ${spec.url.host}\r\n'
            'Authorization: Bearer ••••••\r\n'
            'Accept: */*\r\n'
            'User-Agent: VerbNest/0.25\r\n',
        body: Uint8List(0),
        url: spec.url,
      ),
    );
  }
}

const _pets = '''
[
  {"id": 1, "name": "Biscuit", "species": "dog", "age": 3, "vaccinated": true},
  {"id": 2, "name": "Mochi", "species": "cat", "age": 5, "vaccinated": true},
  {"id": 3, "name": "Pickles", "species": "rabbit", "age": 1, "vaccinated": false},
  {"id": 4, "name": "Juniper", "species": "parrot", "age": 8, "vaccinated": true}
]''';
const _pet =
    '{"id": 1, "name": "Biscuit", "species": "dog", "age": 3, '
    '"vaccinated": true, "owner": {"name": "Sam Lee", "city": "Melbourne"}}';
const _created =
    '{"id": 5, "name": "Biscuit", "species": "dog", "age": 3, '
    '"vaccinated": true, "createdAt": "2026-10-05T04:20:00Z"}';

Future<void> _loadFonts() async {
  final root =
      Platform.environment['FLUTTER_ROOT'] ??
      Platform.environment['flutterRoot'] ??
      '';
  final fonts = '$root/bin/cache/artifacts/material_fonts';
  Future<ByteData> bytes(String path) async =>
      ByteData.sublistView(await File(path).readAsBytes());

  // The app's own fonts, bundled in assets/fonts (the test runs from the app
  // folder). Inter has no Arabic, so Geeza Pro joins its family for the glyphs
  // it lacks.
  final inter = FontLoader('Inter');
  for (final f in const ['Regular', 'Medium', 'SemiBold', 'Bold']) {
    inter.addFont(bytes('assets/fonts/Inter-$f.ttf'));
  }
  inter.addFont(bytes('/System/Library/Fonts/GeezaPro.ttc'));
  await inter.load();
  final jetbrains = FontLoader('JetBrains Mono');
  for (final f in const ['Regular', 'Bold']) {
    jetbrains.addFont(bytes('assets/fonts/JetBrainsMono-$f.ttf'));
  }
  await jetbrains.load();
  final icons = FontLoader('MaterialIcons')
    ..addFont(bytes('$fonts/MaterialIcons-Regular.otf'));
  await icons.load();
  // Arabic: macOS ships Geeza Pro; the fallback needs a name to find it.
  final arabic = FontLoader('GeezaPro')
    ..addFont(bytes('/System/Library/Fonts/GeezaPro.ttc'));
  await arabic.load();
}

class _Ids {
  late String petStore, pets, list, one, create, remove, orders, listOrders;
  late String devEnv, stagingEnv, prodEnv;
}

_Ids _seed(WorkspaceSession s, {String name = 'Pet Store'}) {
  final repo = s.repo;
  repo.name = name;
  final ids = _Ids();
  ids.petStore = repo.createCollection('Pet Store API');
  repo.setContainerAuth(ids.petStore, const BearerAuth(token: '{{token}}'));
  repo.setDescription(ids.petStore, 'Pets and orders for the demo shop.');
  ids.pets = repo.createFolder(ids.petStore, 'Pets');
  ids.orders = repo.createFolder(ids.petStore, 'Orders');

  ids.list = repo.createRequest(
    ids.pets,
    HttpRequestItem(
      id: '',
      name: 'List pets',
      url: '{{baseUrl}}/pets?limit=20',
      params: [KeyValue(key: 'limit', value: '20')],
      headers: [KeyValue(key: 'Accept', value: 'application/json')],
      assertions: const [
        Assertion(target: AssertionTarget.status, value: '200'),
        Assertion(
          target: AssertionTarget.jsonPath,
          op: AssertionOp.exists,
          name: r'$[0].name',
        ),
        Assertion(
          target: AssertionTarget.responseTime,
          op: AssertionOp.lt,
          value: '500',
        ),
      ],
    ),
  );
  ids.one = repo.createRequest(
    ids.pets,
    HttpRequestItem(
      id: '',
      name: 'Get pet',
      url: '{{baseUrl}}/pets/:id',
      pathVars: [KeyValue(key: 'id', value: '1')],
    ),
  );
  ids.create = repo.createRequest(
    ids.pets,
    HttpRequestItem(
      id: '',
      name: 'Create pet',
      method: 'POST',
      url: '{{baseUrl}}/pets',
      headers: [KeyValue(key: 'Content-Type', value: 'application/json')],
      body: const RawBody(
        RawBodyLanguage.json,
        '{\n  "name": "Biscuit",\n  "species": "dog",\n  "age": 3,\n'
        '  "vaccinated": true\n}',
      ),
      scripts: const Scripts(
        pre: "pm.variables.set('requestedAt', new Date().toISOString());",
        post:
            "pm.test('Pet was created', () => {\n"
            '  pm.response.to.have.status(201);\n'
            '  const pet = pm.response.json();\n'
            "  pm.expect(pet.name).to.eql('Biscuit');\n"
            "  pm.environment.set('petId', pet.id);\n"
            '});',
      ),
      assertions: const [
        Assertion(target: AssertionTarget.status, value: '201'),
        Assertion(
          target: AssertionTarget.jsonPath,
          name: r'$.name',
          value: 'Biscuit',
        ),
        Assertion(
          target: AssertionTarget.header,
          op: AssertionOp.contains,
          name: 'Content-Type',
          value: 'json',
        ),
        Assertion(
          target: AssertionTarget.responseTime,
          op: AssertionOp.lt,
          value: '500',
        ),
      ],
    ),
  );
  ids.remove = repo.createRequest(
    ids.pets,
    HttpRequestItem(
      id: '',
      name: 'Delete pet',
      method: 'DELETE',
      url: '{{baseUrl}}/pets/:id',
      pathVars: [KeyValue(key: 'id', value: '1')],
    ),
  );
  ids.listOrders = repo.createRequest(
    ids.orders,
    HttpRequestItem(id: '', name: 'List orders', url: '{{baseUrl}}/orders'),
  );
  repo.createRequest(
    ids.orders,
    HttpRequestItem(
      id: '',
      name: 'Place order',
      method: 'POST',
      url: '{{baseUrl}}/orders',
    ),
  );
  repo.setFavourite(ids.list, true);

  repo.saveEnvironment(
    const Environment(
      id: 'env-dev',
      name: 'Development',
      variables: [
        Variable(key: 'baseUrl', value: 'https://api.petstore.dev/v2'),
        Variable(key: 'token', value: 'dev-3f9a6c21b7', secret: true),
        Variable(key: 'petId', value: '1'),
      ],
    ),
  );
  repo.saveEnvironment(
    const Environment(
      id: 'env-staging',
      name: 'Staging',
      variables: [
        Variable(key: 'baseUrl', value: 'https://staging.petstore.dev/v2'),
        Variable(key: 'token', value: 'stg-81d0e4a9c5', secret: true),
      ],
    ),
  );
  repo.saveEnvironment(
    const Environment(
      id: 'env-prod',
      name: 'Production',
      variables: [
        Variable(key: 'baseUrl', value: 'https://api.petstore.com/v2'),
        Variable(key: 'token', value: 'prd-c47b19e0d2', secret: true),
      ],
    ),
  );
  repo.defaultEnvironmentId = 'env-dev';
  repo.saveVariables(VariableOwner.global, const [
    Variable(key: 'tenant', value: 'acme'),
    Variable(key: 'apiVersion', value: 'v2'),
  ]);
  return ids;
}

class _App {
  _App(this.tester, this.session, this.ids);
  final WidgetTester tester;
  final WorkspaceSession session;
  final _Ids ids;
  final failures = <String>[];

  Future<void> settle() async {
    for (var i = 0; i < 12; i++) {
      await tester.pump(const Duration(milliseconds: 50));
    }
  }

  Future<void> tapKey(Object key) async {
    await tester.tap(find.byKey(key is Key ? key : Key('$key')).first);
    await settle();
  }

  Future<void> tapText(String text) async {
    // Tabs can sit past the screen edge on a phone.
    await tester.ensureVisible(find.text(text).first);
    await tester.tap(find.text(text).first);
    await settle();
  }

  Future<void> open(String id) async {
    await tapKey('node-$id');
  }

  Future<void> send() async {
    await tapKey('send');
    // Secrets only go to approved hosts; approve the demo host like a user.
    final allow = find.byKey(const Key('secret-host-allow'));
    if (allow.evaluate().isNotEmpty) await tapKey('secret-host-allow');
    await tester.pump(const Duration(milliseconds: 300));
    await settle();
  }

  Future<void> snap(String name) async {
    final only = _profile.only;
    if (only != null && !only.contains(name)) return;
    await settle();
    final boundary = tester.renderObject<RenderRepaintBoundary>(
      find.byKey(_boundary),
    );
    await tester.runAsync(() async {
      final image = await boundary.toImage(pixelRatio: _ratio);
      final data = await image.toByteData(format: ui.ImageByteFormat.png);
      final file = File('$_out/$name.png')..createSync(recursive: true);
      file.writeAsBytesSync(data!.buffer.asUint8List());
      stdout.writeln('  wrote $name.png (${image.width}x${image.height})');
    });
  }

  /// Runs one screen; a failure is recorded so the other screens still render.
  Future<void> shot(String name, Future<void> Function() body) async {
    try {
      await body();
      await snap(name);
    } on Object catch (e, st) {
      if (_profile.only case final only? when !only.contains(name)) return;
      failures.add(
        '$name: $e\n${st.toString().split('\n').take(5).join('\n')}',
      );
    }
  }

  /// Pops every dialog and pushed page back to the main window.
  Future<void> closeDialogs() async {
    final nav = tester.state<NavigatorState>(find.byType(Navigator).first);
    while (nav.canPop()) {
      nav.pop();
      await settle();
    }
  }
}

Future<_App> _launch(
  WidgetTester tester, {
  bool dark = false,
  String? language,
  String name = 'Pet Store',
}) async {
  tester.view.physicalSize = Size(
    _logical.width * _ratio,
    _logical.height * _ratio,
  );
  tester.view.devicePixelRatio = _ratio;
  addTearDown(tester.view.reset);
  debugDefaultTargetPlatformOverride = _profile.platform;
  final session = WorkspaceSession.memory();
  addTearDown(session.close);
  final ids = _seed(session, name: name);
  final dir = Directory.systemTemp.createTempSync('verbnest-shots');
  addTearDown(() => dir.deleteSync(recursive: true));
  for (final w in ['Pet Store', 'Team Sandbox', 'Personal notes']) {
    final f = File('${dir.path}/$w.verbnest')..createSync();
    session.local.touchWorkspace(
      w == 'Pet Store' ? session.repo.workspaceId : 'ws-$w',
      w,
      f.path,
    );
  }
  session.repo.settings = {
    ...session.repo.settings,
    'themeMode': dark ? 'dark' : 'light',
    'language': ?language,
  };
  await tester.pumpWidget(
    RepaintBoundary(
      key: _boundary,
      child: ProviderScope(
        overrides: [
          sessionProvider.overrideWithValue(session),
          engineProvider.overrideWithValue(_ShotEngine()),
          scriptEngineProvider.overrideWithValue(_ShotScripts()),
        ],
        child: WorkspaceHost(initial: session, child: const VerbnestApp()),
      ),
    ),
  );
  final app = _App(tester, session, ids);
  await app.settle();
  return app;
}

/// testWidgets that clears the platform override before the binding checks
/// its debug variables, which happens before any tearDown callback.
void _shots(
  String name,
  Future<void> Function(WidgetTester) body, {
  required bool skip,
}) => testWidgets(name, (t) async {
  try {
    await body(t);
  } finally {
    debugDefaultTargetPlatformOverride = null;
  }
}, skip: skip);

void main() {
  final enabled = (_out ?? '').isNotEmpty;
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() async {
    if (enabled) await _loadFonts();
  });

  _shots('main window: collections, request and response', (t) async {
    final a = await _launch(t);
    await a.open(a.ids.petStore);
    await a.open(a.ids.pets);
    await a.open(a.ids.list);
    await a.send();
    await a.snap('01-request-and-response');

    await a.shot('02-create-pet-body', () async {
      await a.open(a.ids.create);
      await a.tapText('Body');
    });

    await a.shot('03-auth-inherited-bearer', () async {
      await a.tapText('Auth');
    });

    await a.shot('04-scripts', () async {
      await a.send();
      await a.tapText('Scripts');
      await t.tap(find.textContaining('Post-response').first);
      await a.settle();
    });

    await a.shot('05-assertions-and-test-results', () async {
      await a.tapText('Assertions');
      await a.send();
      await t.tap(find.textContaining('Tests').first);
      await a.settle();
    });

    await a.shot('06-response-headers', () async {
      await t.tap(find.textContaining('Headers').last);
      await a.settle();
    });

    await a.shot('07-command-palette', () async {
      await t.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
      await t.sendKeyEvent(LogicalKeyboardKey.keyK);
      await t.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
      await a.settle();
      await t.enterText(find.byKey(const Key('palette-input')), 'pet');
      await a.settle();
    });
    await a.closeDialogs();

    await a.shot('08-generate-code', () async {
      await a.tapKey('menu-${a.ids.list}');
      await a.tapText('Generate code…');
    });
    await a.closeDialogs();

    await a.shot('09-save-and-browse-examples', () async {
      await a.open(a.ids.list);
      await a.send();
      await a.tapKey('examples');
      await t.tap(find.text('Save current response'));
      await a.settle();
    });
    await a.closeDialogs();

    await a.shot('10-search-workspace', () async {
      await a.tapKey('sidebar-more');
      await a.tapKey('search');
      await t.enterText(find.byType(TextField).last, 'pet');
      await a.settle();
    });
    await a.closeDialogs();

    await a.shot('11-import', () async {
      await a.tapKey('sidebar-more');
      await a.tapKey('import');
    });
    await a.closeDialogs();

    await a.shot('12-workspaces', () async {
      await a.tapKey('sidebar-more');
      await a.tapKey('workspaces');
    });
    await a.closeDialogs();

    await a.shot('13-collection-runner', () async {
      await a.tapKey('menu-${a.ids.pets}');
      await a.tapText('Run…');
    });
    await a.closeDialogs();

    await a.shot('14-history', () async {
      await a.tapText('History');
    });

    await a.shot('15-console', () async {
      await a.tapKey('console-open');
    });
    await a.closeDialogs();

    await a.shot('16-environments', () async {
      await a.tapText('Environments');
      await a.tapText('Development');
    });

    await a.shot('17-settings', () async {
      await a.tapText('Settings');
    });

    expect(a.failures, isEmpty, reason: a.failures.join('\n'));
  }, skip: !enabled || _profile.phone);

  _shots('phone: bottom navigation and full-screen request', (t) async {
    final a = await _launch(t);
    await a.shot('01-collections', () async {
      await a.open(a.ids.petStore);
      await a.open(a.ids.pets);
    });

    await a.shot('02-request-and-response', () async {
      await a.open(a.ids.list);
      await a.send();
    });

    await a.shot('03-create-pet-body', () async {
      await a.closeDialogs();
      await a.open(a.ids.create);
      await a.tapText('Body');
    });

    await a.shot('04-auth-inherited-bearer', () async {
      await a.tapText('Auth');
    });

    await a.shot('05-assertions-and-test-results', () async {
      await a.tapText('Assertions');
      await a.send();
      await t.tap(find.textContaining('Tests').first);
      await a.settle();
    });

    await a.shot('06-response-headers', () async {
      await t.tap(find.textContaining('Headers').last);
      await a.settle();
    });

    await a.shot('07-history', () async {
      await a.closeDialogs();
      await a.tapText('History');
    });

    await a.shot('08-environments', () async {
      await a.tapText('Environments');
      await a.tapText('Development');
    });

    await a.shot('09-settings', () async {
      await a.closeDialogs();
      await a.tapText('Settings');
    });

    expect(a.failures, isEmpty, reason: a.failures.join('\n'));
  }, skip: !enabled || !_profile.phone);

  _shots('phone: dark theme', (t) async {
    final a = await _launch(t, dark: true);
    await a.open(a.ids.petStore);
    await a.open(a.ids.pets);
    await a.open(a.ids.list);
    await a.send();
    await a.snap('10-dark-theme');
  }, skip: !enabled || !_profile.phone);

  _shots('dark theme', (t) async {
    final a = await _launch(t, dark: true);
    await a.open(a.ids.petStore);
    await a.open(a.ids.pets);
    await a.open(a.ids.list);
    await a.send();
    await a.snap('18-dark-theme');
  }, skip: !enabled || _profile.phone);
}
