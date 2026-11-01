// The App Store review walk-through, for a PHYSICAL iPhone or iPad only.
//
// It starts the app on a fresh workspace and drives it the way a person
// would, slowly and with the real on-screen keyboard, so a screen recording
// of the device shows the app from launch through each check. It skips itself
// on a simulator, on Android and on desktops.
//
// Run it (and record the screen) with scripts/app_review_recording.sh.
import 'dart:convert';
import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:verbnest_app/src/app.dart';
import 'package:verbnest_app/src/state/editor_state.dart';
import 'package:verbnest_app/src/state/session.dart';
import 'package:verbnest_app/src/state/tree_state.dart';
import 'package:verbnest_app/src/workspace_host.dart';

bool get _physicalIos =>
    Platform.isIOS &&
    !Platform.environment.containsKey('SIMULATOR_DEVICE_NAME');

/// A pause long enough to read the screen in a recording.
Future<void> _beat(WidgetTester t, [double seconds = 1.5]) async {
  await t.pump();
  await Future<void>.delayed(Duration(milliseconds: (seconds * 1000).round()));
  await t.pump();
}

void _say(String step) =>
    // ignore: avoid_print
    print('APP-REVIEW ${DateTime.now().toIso8601String()} $step');

/// Types [text] into the field under [field] one character at a time with the
/// real keyboard open, and checks after every character that the keyboard and
/// the focus are still there (the bug fixed in 0.65.3 and 0.65.4).
Future<void> _type(WidgetTester t, Finder field, String text) async {
  await t.tap(field);
  await _beat(t, 0.8);
  final editable = find.descendant(
    of: field,
    matching: find.byType(EditableText),
  );
  final target = editable.evaluate().isEmpty ? field : editable;
  var typed = '';
  for (final ch in text.split('')) {
    typed += ch;
    final state = t.state<EditableTextState>(target);
    // The same call the keyboard makes for each letter it sends.
    state.updateEditingValue(
      TextEditingValue(
        text: typed,
        selection: TextSelection.collapsed(offset: typed.length),
      ),
    );
    await t.pump(const Duration(milliseconds: 140));
    await Future<void>.delayed(const Duration(milliseconds: 90));
    expect(
      t.state<EditableTextState>(target).widget.focusNode.hasFocus,
      isTrue,
      reason: 'the field lost focus after "$typed"',
    );
    expect(
      t.view.viewInsets.bottom,
      greaterThan(0),
      reason: 'the keyboard closed after "$typed"',
    );
  }
  await _beat(t, 0.6);
}

Future<void> _tapText(WidgetTester t, String text, {bool last = false}) async {
  final f = find.text(text).hitTestable();
  expect(f, findsWidgets, reason: 'no "$text" on screen');
  await t.tap(last ? f.last : f.first);
  await _beat(t);
}

void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets(
    'App Store review walk-through on a physical iPhone',
    (t) async {
      // The real keyboard must open, so the test keyboard stays out.
      t.testTextInput.unregister();

      // A server inside the app's own process: no network needed and nothing
      // leaves the device. It answers with the headers it was sent.
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      addTearDown(() => server.close(force: true));
      server.listen((req) async {
        final headers = <String, String>{};
        req.headers.forEach((k, v) => headers[k] = v.join(', '));
        req.response
          ..headers.contentType = ContentType.json
          ..write(
            jsonEncode({
              'service': 'VerbNest review server',
              'method': req.method,
              'path': req.uri.path,
              'headers': headers,
              'pets': ['Rex', 'Mia', 'Biscuit'],
            }),
          );
        await req.response.close();
      });

      // 1. Start up on a fresh workspace.
      _say('1 launch on a new workspace');
      final dir = await WorkspaceSession.workspacesDir();
      final path =
          '${dir.path}/app-review-${DateTime.now().millisecondsSinceEpoch}.verbnest';
      final session = await WorkspaceSession.openFile(path, create: true);
      addTearDown(() {
        for (final suffix in ['', '-wal', '-shm']) {
          final f = File('$path$suffix');
          if (f.existsSync()) f.deleteSync();
        }
      });
      await t.pumpWidget(
        WorkspaceHost(initial: session, child: const VerbnestApp()),
      );
      await _beat(t, 4);
      expect(find.text('Collections'), findsWidgets);

      // 2. Create a collection.
      _say('2 create a collection');
      await t.tap(find.byKey(const Key('new-collection')));
      await _beat(t);
      await _type(t, find.byKey(const Key('name-field')), 'App Review Demo');
      await _tapText(t, 'Create');
      expect(find.text('App Review Demo'), findsOneWidget);
      await _beat(t);

      // 3. Add a request to it from its menu.
      _say('3 add a request');
      final tile = find.widgetWithText(ListTile, 'App Review Demo');
      await t.tap(
        find.descendant(of: tile, matching: find.byIcon(Icons.more_vert)),
      );
      await _beat(t);
      await _tapText(t, 'New request');
      await _type(t, find.byKey(const Key('name-field')), 'List pets');
      await _tapText(t, 'Create');
      await _beat(t, 2);

      // 4. Type the address with the real keyboard.
      _say('4 enter the address');
      final url = 'http://127.0.0.1:${server.port}/pets';
      await _type(t, find.byKey(const Key('url')), url);

      // 5. Add a header: the keyboard must stay up for key and value.
      _say('5 add a header (keyboard stays up)');
      FocusManager.instance.primaryFocus?.unfocus();
      await _beat(t);
      await _tapText(t, 'Headers');
      await t.tap(find.byKey(const Key('headers-add')));
      await _beat(t);
      await _type(t, find.byKey(const ValueKey('headers-key-0')), 'X-Demo');
      await _type(
        t,
        find.byKey(const ValueKey('headers-value-0')),
        'app-review',
      );
      FocusManager.instance.primaryFocus?.unfocus();
      await _beat(t);

      // 6. Send it and read the answer.
      _say('6 send and read the response');
      await t.tap(find.byKey(const Key('send')));
      await t.pump();
      for (var i = 0; i < 40; i++) {
        if (find.byKey(const Key('response-status')).evaluate().isNotEmpty) {
          break;
        }
        await Future<void>.delayed(const Duration(milliseconds: 250));
        await t.pump();
      }
      await _beat(t, 3);
      expect(find.byKey(const Key('response-status')), findsOneWidget);
      final container = ProviderScope.containerOf(
        t.element(find.byType(VerbnestApp)),
      );
      final tabs = container.read(tabsProvider);
      final response = container.read(editorProvider(tabs.active!)).response;
      expect(response, isNotNull);
      expect(response!.status, 200);
      expect(response.bodyText, contains('app-review'));
      expect(response.bodyText, contains('Biscuit'));

      // 7. Look through the response.
      _say('7 response headers');
      await _tapText(t, 'Headers', last: true);
      await _beat(t, 2.5);

      // 8. Leave the request and visit the other screens.
      _say('8 back to the collections');
      await t.pageBack();
      await _beat(t, 2);
      for (final name in ['History', 'Environments', 'Settings']) {
        _say('9 $name');
        await _tapText(t, name, last: true);
        await _beat(t, 2.5);
      }
      _say('10 done');
      await _beat(t, 2);
      binding.reportData = {'steps': 'completed'};
    },
    skip: !_physicalIos,
    timeout: const Timeout(Duration(minutes: 8)),
  );
}
