import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:verbnest_app/src/app.dart';
import 'package:verbnest_app/src/state/editor_state.dart';
import 'package:verbnest_app/src/state/session.dart';
import 'package:verbnest_core/verbnest_core.dart';

import '../test/support/matrix_support.dart' show FakeEngine;

/// On the real renderer: changing the body view (Pretty, Raw, Hex, Table) is
/// one swap. The first frame after the tap is the same image as the settled
/// screen, so nothing moves, fades or pops in a frame later.
final _key = GlobalKey();

Future<Uint8List> _frame(WidgetTester t) async {
  await t.pump();
  final b = _key.currentContext!.findRenderObject()! as RenderRepaintBoundary;
  final img = await b.toImage(pixelRatio: t.view.devicePixelRatio);
  final data = await img.toByteData(format: ui.ImageByteFormat.rawRgba);
  img.dispose();
  return data!.buffer.asUint8List();
}

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('changing the body view is one swap', (t) async {
    final s = WorkspaceSession.memory();
    addTearDown(s.close);
    final col = s.repo.createCollection('Pet Store API');
    final id = s.repo.createRequest(
      col,
      HttpRequestItem(
        id: '',
        name: 'List pets',
        url: 'https://api.petstore.dev/v2/pets',
      ),
    );
    final c = ProviderContainer(
      overrides: [
        sessionProvider.overrideWithValue(s),
        engineProvider.overrideWithValue(FakeEngine(items: 40)),
      ],
    );
    addTearDown(c.dispose);
    await t.pumpWidget(
      RepaintBoundary(
        key: _key,
        child: UncontrolledProviderScope(
          container: c,
          child: const VerbnestApp(),
        ),
      ),
    );
    await t.pumpAndSettle();
    if (find.byKey(Key('node-$id')).evaluate().isEmpty) {
      await t.tap(find.byKey(Key('node-$col')));
      await t.pumpAndSettle();
    }
    await t.tap(find.byKey(Key('node-$id')));
    await t.pumpAndSettle();
    await t.tap(find.byKey(const Key('send')).first);
    for (var i = 0; i < 50; i++) {
      await t.pump(const Duration(milliseconds: 100));
      if (find.byKey(const Key('body-view')).evaluate().isNotEmpty) break;
    }
    await t.pumpAndSettle();
    for (final mode in ['Table', 'Raw', 'Hex', 'Pretty', 'Table', 'Raw']) {
      final segment = find.descendant(
        of: find.byKey(const Key('body-view')),
        matching: find.text(mode),
      );
      if (segment.evaluate().isEmpty) {
        // A narrow pane has the table in the body menu.
        await t.tap(find.byKey(const Key('body-more')));
        await t.pumpAndSettle();
        await t.tap(find.byKey(const Key('menu-table')));
      } else {
        await t.tap(segment);
      }
      final first = await _frame(t);
      await t.pump(const Duration(milliseconds: 300));
      final settled = await _frame(t);
      expect(
        listEquals(first, settled),
        isTrue,
        reason: 'the screen changed after the first frame of $mode',
      );
    }
    await t.pump(EditorNotifier.saveDelay);
  });
}
