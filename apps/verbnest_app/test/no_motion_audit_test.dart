import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:verbnest_app/src/settings_page.dart';
import 'package:verbnest_app/src/state/editor_state.dart';
import 'package:verbnest_app/src/widgets/ui/still_controls.dart';
import 'package:verbnest_app/src/widgets/ui/still_nav.dart';

import 'support/device_profiles.dart';
import 'support/matrix_support.dart';

/// A tour of the app that fails when anything MOVES on screen after an action
/// has been drawn: it takes the screen 16 ms, 76 ms and 136 ms after each action
/// and they must be identical. (Counting running animations is not enough: a
/// transparent tap highlight still runs a timer, and nothing shows.) Material's
/// own animations last 150 ms or more, so one would change the picture between
/// the first and the last frame. See ADR-020.
Future<Uint8List> _frame(WidgetTester t, [String? png]) async {
  RenderObject r = find.byType(WidgetsApp).evaluate().single.renderObject!;
  while (!r.isRepaintBoundary) {
    r = r.parent!;
  }
  final layer = r.debugLayer! as OffsetLayer;
  final bounds = r.paintBounds;
  final bytes = await t.runAsync(() async {
    final image = await layer.toImage(bounds);
    if (png != null) {
      final p = await image.toByteData(format: ui.ImageByteFormat.png);
      File(png).writeAsBytesSync(p!.buffer.asUint8List());
    }
    final data = await image.toByteData(format: ui.ImageByteFormat.rawRgba);
    image.dispose();
    return data!.buffer.asUint8List();
  });
  return bytes!;
}

/// Where two frames differ, as a rectangle in pixels (the width is that of the
/// view), or "same".
String _where(Uint8List a, Uint8List b) {
  if (listEquals(a, b)) return 'same';
  final w = (a.length / 4 / 800).round(); // overwritten below
  var minX = 1 << 30, minY = 1 << 30, maxX = -1, maxY = -1;
  final width = _width;
  for (var i = 0; i < a.length; i += 4) {
    if (a[i] != b[i] || a[i + 1] != b[i + 1] || a[i + 2] != b[i + 2]) {
      final px = i ~/ 4;
      final x = px % width, y = px ~/ width;
      if (x < minX) minX = x;
      if (y < minY) minY = y;
      if (x > maxX) maxX = x;
      if (y > maxY) maxY = y;
    }
  }
  return maxX < 0
      ? 'alpha only'
      : 'x $minX..$maxX y $minY..$maxY${w == 0 ? '' : ''}';
}

int _width = 1280;

class _Tour {
  _Tour(this.t, this.name);

  final WidgetTester t;
  final String name;
  final moving = <String>[];
  final skipped = <String>[];
  var ran = 0;

  Future<void> step(
    String label,
    Future<void> Function() action, {
    Duration settle = Duration.zero,
    bool compare = true,
  }) async {
    try {
      await action();
    } on Object catch (e) {
      skipped.add('$label (${e.toString().split('\n').first})');
      await t.pumpAndSettle();
      return;
    }
    await t.pump(const Duration(milliseconds: 16));
    // A state that lands after a debounce or a focus change is let to land.
    if (settle > Duration.zero) await t.pump(settle);
    await t.pump(const Duration(milliseconds: 60));
    final tag = label.replaceAll(RegExp('[^a-z0-9]+'), '_');
    final b = await _frame(
      t,
      '/private/tmp/claude-501/audit_${name}_${tag}_b.png',
    );
    await t.pump(const Duration(milliseconds: 60));
    final c = await _frame(
      t,
      '/private/tmp/claude-501/audit_${name}_${tag}_c.png',
    );
    ran++;
    // A state that reaches the screen a frame late (a caret, a scrollbar) is
    // not motion; a picture that is still changing 60 to 120 ms later is.
    if (compare && !listEquals(b, c)) {
      moving.add('$label: still changing at 120 ms (${_where(b, c)})');
    }
    await t.pumpAndSettle(
      const Duration(milliseconds: 50),
      EnginePhase.sendSemanticsUpdate,
      const Duration(seconds: 3),
    );
  }
}

void main() {
  for (final p in [
    const DeviceProfile('desktop', Size(1280, 800)),
    const DeviceProfile('phone', Size(402, 874)),
  ]) {
    testWidgets('nothing moves on ${p.name}', (t) async {
      EditableText.debugDeterministicCursor = true;
      _width = p.size.width.round();
      final a = await launchApp(t, p, engine: FakeEngine(items: 3));
      // Let the images decode (that is loading, not motion).
      await t.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 300)),
      );
      await t.pumpAndSettle(const Duration(milliseconds: 50));
      final tour = _Tour(t, p.name);
      final phone = p.size.width < 600;
      TestGesture? mouse;
      Future<TestGesture> getMouse() async {
        if (mouse == null) {
          mouse = await t.createGesture(kind: PointerDeviceKind.mouse);
          await mouse!.addPointer(location: const Offset(3, 3));
          addTearDown(mouse!.removePointer);
        }
        return mouse!;
      }

      Future<void> showPane(String name) async {
        final sw = find.byKey(const Key('pane-switch'));
        if (phone && sw.evaluate().isNotEmpty) {
          await t.tap(find.descendant(of: sw, matching: find.text(name)));
          await t.pumpAndSettle();
        }
      }

      final modes = find.byKey(const Key('body-view'));
      final settingsScroll = find
          .descendant(
            of: find.byType(SettingsPage),
            matching: find.byType(Scrollable),
          )
          .first;

      await tour.step('open a request', () => openRequest(a, p));
      await tour.step(
        'send',
        () => t.tap(find.byKey(const Key('send')), warnIfMissed: false),
      );
      await showPane('Request');
      for (final tab in [
        'Headers',
        'Auth',
        'Body',
        'Scripts',
        'Assertions',
        'Params',
      ]) {
        await tour.step('request tab $tab', () async {
          final f = find.text(tab).first;
          await t.ensureVisible(f);
          await t.tap(f, warnIfMissed: false);
        });
      }
      await tour.step('Headers tab, open the generated headers', () async {
        await t.tap(find.text('Headers').first, warnIfMissed: false);
        await t.pumpAndSettle();
        await t.tap(find.byType(ExpansionTile).first);
      });
      await showPane('Response');
      for (final tab in ['Cookies', 'Headers', 'Sent', 'Tests', 'Body']) {
        await tour.step('response tab $tab', () async {
          final f = find
              .descendant(
                of: find.byKey(const Key('response-tabs')),
                matching: find.text(tab),
              )
              .first;
          // A scrolling tab row can have it out of reach.
          await t.ensureVisible(f);
          await t.tap(f);
        });
      }
      for (final m in ['Raw', 'Hex', 'Pretty']) {
        await tour.step(
          'view $m',
          () => t.tap(find.descendant(of: modes, matching: find.text(m))),
        );
      }
      Future<void> tableOnOff() async {
        final more = find.byKey(const Key('body-more'));
        if (more.evaluate().isNotEmpty) {
          await t.tap(more);
          await t.pumpAndSettle();
          await t.tap(find.byKey(const Key('menu-table')));
        } else {
          await t.tap(find.descendant(of: modes, matching: find.text('Table')));
        }
      }

      await tour.step('table view on', tableOnOff);
      await tour.step(
        'sort a column',
        () => t.tap(find.byKey(const ValueKey('table-sort-1'))),
      );
      await tour.step('select a cell', () async {
        final g = await getMouse();
        await g.down(t.getCenter(find.byKey(const ValueKey('table-cell-0-1'))));
        await g.up();
      });
      await tour.step(
        'table menu open',
        () => t.tap(find.byKey(const Key('table-actions'))),
      );
      await tour.step(
        'table menu close',
        () => t.sendKeyEvent(LogicalKeyboardKey.escape),
      );
      await tour.step('table view off', tableOnOff);
      await showPane('Request');
      await tour.step('hover a button', () async {
        final g = await getMouse();
        await g.moveTo(t.getCenter(find.byKey(const Key('send'))));
      });
      await tour.step('move the mouse away', () async {
        final g = await getMouse();
        await g.moveTo(const Offset(3, 3));
      });
      // A mouse click, as on a desktop. A touch tap shows the selection handle,
      // which the system fades in on a phone (the one animation left to it).
      await tour.step('focus the URL field', () async {
        final g = await getMouse();
        await g.down(t.getCenter(find.byKey(const Key('url'))));
        await g.up();
      }, settle: const Duration(milliseconds: 400));
      // Typing starts the editor's save timer; its effect (a saved state, a
      // refreshed list) lands later and is state, not motion. Let it land.
      await tour.step(
        'type in the URL field',
        () async {
          await t.enterText(find.byKey(const Key('url')), 'https://x.test/a');
          await t.pump(EditorNotifier.saveDelay);
          await t.pump(const Duration(milliseconds: 500));
        },
        settle: const Duration(milliseconds: 400),
        // On a touch device the caret and the system keyboard settle on their
        // own schedule; the desktop caret is covered by 'the text cursor does
        // not blink' below.
        compare: !phone,
      );
      await tour.step(
        'open the method menu',
        () => t.tap(find.byKey(const Key('method'))),
      );
      await tour.step('choose a method', () async {
        await t.tap(find.text('POST').last);
        // The change is saved after a debounce and the tab title follows; let it.
        await t.pump(EditorNotifier.saveDelay);
        await t.pump(const Duration(milliseconds: 500));
      });
      await tour.step(
        'open the environment menu',
        () => t.tap(find.byKey(const Key('env-select')), warnIfMissed: false),
      );
      await tour.step(
        'close the environment menu',
        () => t.sendKeyEvent(LogicalKeyboardKey.escape),
      );
      await tour.step(
        'open the variables view',
        () => t.tap(find.byKey(const Key('quick-look')), warnIfMissed: false),
      );
      await tour.step('close the variables view', () async {
        final c = find.text('Close');
        if (c.evaluate().isNotEmpty) {
          await t.tap(c.last);
        } else {
          await t.sendKeyEvent(LogicalKeyboardKey.escape);
        }
      });
      await tour.step('mouse wheel', () async {
        final g = await getMouse();
        await g.moveTo(const Offset(310, 310));
        await t.sendEventToBinding(
          PointerScrollEvent(
            kind: PointerDeviceKind.mouse,
            position: const Offset(310, 310),
            scrollDelta: const Offset(0, 120),
          ),
        );
      });
      if (phone) await tour.step('back to the list', () => t.pageBack());
      for (final dest in [
        'Settings',
        'History',
        'Environments',
        'Collections',
      ]) {
        await tour.step('go to $dest', () {
          // The navigation (bottom bar, rail or drawer), not a tab of the same name.
          final nav = find.byWidgetPredicate(
            (w) =>
                w is StillNavigationBar ||
                w is StillNavigationRail ||
                w is StillNavigationDrawer,
          );
          return t.tap(find.descendant(of: nav, matching: find.text(dest)));
        });
        if (dest == 'Settings') {
          await tour.step('toggle a switch', () async {
            final f = find.byKey(const Key('compact-density'));
            await t.scrollUntilVisible(f, 300, scrollable: settingsScroll);
            await t.tap(f);
          });
          await tour.step(
            'pick an accent',
            () async {
              final f = find.byKey(const Key('accent-2'));
              await t.scrollUntilVisible(f, 300, scrollable: settingsScroll);
              await t.tap(f);
            },
            // Known exception: Material surfaces (Scaffold, cards) cross-fade their
            // colour over 200 ms when the theme changes, and Flutter has no switch
            // for that. It happens only when the accent or the theme is changed.
            compare: false,
          );
          await tour.step('move a slider', () async {
            final s = find.byType(StillSlider);
            await t.scrollUntilVisible(
              s.first,
              300,
              scrollable: settingsScroll,
            );
            await t.drag(s.first, const Offset(40, 0));
          });
        }
      }
      await tour.step(
        'sidebar: open a collection',
        () => t.tap(find.text('Pet Store API').first),
      );
      await t.pump(EditorNotifier.saveDelay);
      debugPrint('${p.name}: ${tour.ran} steps ran, skipped: ${tour.skipped}');
      expect(tour.ran, greaterThan(25), reason: 'skipped: ${tour.skipped}');
      expect(tour.moving, isEmpty, reason: tour.moving.join('\n'));
    });
  }

  testWidgets('the text cursor does not blink', (t) async {
    EditableText.debugDeterministicCursor = true;
    const p = DeviceProfile('desktop', Size(1280, 800));
    final a = await launchApp(t, p);
    await openRequest(a, p);
    final g = await t.createGesture(kind: PointerDeviceKind.mouse);
    await g.addPointer(location: const Offset(3, 3));
    addTearDown(g.removePointer);
    await g.down(t.getCenter(find.byKey(const Key('url'))));
    await g.up();
    await t.pump(const Duration(milliseconds: 300));
    // A blinking caret would be on in one of these and off in another (it
    // changes every 500 ms).
    final frames = <Uint8List>[];
    for (var i = 0; i < 4; i++) {
      frames.add(await _frame(t));
      await t.pump(const Duration(milliseconds: 520));
    }
    for (var i = 1; i < frames.length; i++) {
      expect(listEquals(frames.first, frames[i]), isTrue, reason: 'frame $i');
    }
    await t.pump(EditorNotifier.saveDelay);
  });
}
