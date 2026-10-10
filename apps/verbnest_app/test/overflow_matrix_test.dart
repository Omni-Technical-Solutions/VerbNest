import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:verbnest_app/src/app.dart';
import 'package:verbnest_app/src/state/session.dart';
import 'package:verbnest_app/src/state/tree_state.dart';
import 'package:verbnest_core/verbnest_core.dart';

/// Material 3 window size classes plus the devices this app ships on:
/// small Android, Android, iPhone, widest compact, Medium start, iPad
/// portrait, desktop, Large and Extra-large.
const _widths = [
  320.0,
  360.0,
  402.0,
  599.0,
  600.0,
  840.0,
  1032.0,
  1280.0,
  1600.0,
];

/// Top-level destinations, by the label the bar or rail shows.
const _destinations = ['History', 'Environments', 'Settings', 'Collections'];

void main() {
  for (final w in _widths) {
    testWidgets('no layout overflow at ${w.toInt()} pt', (t) async {
      t.view.physicalSize = Size(w, w < 600 ? 874 : 900);
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
      s.repo.saveEnvironment(
        const Environment(
          id: 'env-dev',
          name: 'Development',
          variables: [
            Variable(key: 'baseUrl', value: 'https://api.petstore.dev'),
          ],
        ),
      );
      final c = ProviderContainer(
        overrides: [sessionProvider.overrideWithValue(s)],
      );
      addTearDown(c.dispose);
      await t.pumpWidget(
        UncontrolledProviderScope(container: c, child: const VerbnestApp()),
      );
      await t.pump(const Duration(milliseconds: 300));
      expect(t.takeException(), isNull, reason: 'first frame');

      for (final label in _destinations) {
        await t.tap(find.text(label).last);
        await t.pump(const Duration(milliseconds: 400));
        expect(t.takeException(), isNull, reason: label);
      }
      // A request open in the editor (opens full screen on a phone).
      c.read(tabsProvider.notifier).open(id);
      await t.pump(const Duration(milliseconds: 400));
      expect(t.takeException(), isNull, reason: 'request editor');
    });
  }
}
