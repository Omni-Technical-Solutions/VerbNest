import 'dart:async';

import 'package:flutter/scheduler.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:verbnest_app/src/state/editor_state.dart';
import 'package:verbnest_app/src/widgets/request_editor/url_bar.dart';
import 'package:verbnest_app/src/widgets/ui/ui.dart';
import 'package:verbnest_http/verbnest_http.dart';

import 'support/device_profiles.dart';
import 'support/matrix_support.dart';

/// Sending a request and changing the body view must not animate beyond the
/// press feedback on the button that was tapped and, while a request is in
/// flight, the thin progress line. Counts the animations running
/// (`transientCallbackCount`) instead of looking at pixels.
class _Gate extends FakeEngine {
  _Gate() : super(items: 3);
  final gate = Completer<void>();

  @override
  Future<HttpResponseRecord> send(
    HttpRequestSpec spec, {
    CancelToken? cancel,
  }) async {
    await gate.future;
    return super.send(spec, cancel: cancel);
  }
}

int get _running => SchedulerBinding.instance.transientCallbackCount;

const _desktop = DeviceProfile('desktop-1280x800', Size(1280, 800));
const _phone = DeviceProfile('iphone-402x874', Size(402, 874));

void main() {
  for (final p in [_desktop, _phone]) {
    testWidgets('sending a request does not animate, ${p.name}', (t) async {
      final engine = _Gate();
      final a = await launchApp(t, p, engine: engine);
      await openRequest(a, p);
      await t.pumpAndSettle(const Duration(milliseconds: 100));
      expect(_running, 0);

      await t.tap(find.byKey(const Key('send')), warnIfMissed: false);
      await t.pump();
      // Send and Cancel swap at once, with no fade between them.
      expect(
        find.descendant(
          of: find.byType(UrlBar),
          matching: find.byType(AnimatedSwitcher),
        ),
        findsNothing,
      );
      // The progress shown while it is in flight is a still bar, not a sliding
      // one, so nothing runs at all.
      await t.pump(const Duration(seconds: 1));
      // A finished animation is only noticed on the next frame.
      await t.pump(const Duration(milliseconds: 16));
      expect(find.byType(LinearProgressIndicator), findsNothing);
      expect(_running, 0, reason: 'nothing animates while sending');
      // The placeholder for the response is still, not pulsing.
      expect(find.byType(Skeleton), findsOneWidget);

      // The response arrives: it replaces the placeholder at once. A scrollbar
      // can keep one internal timer for a frame or two (nothing moves), and
      // after 300 ms nothing is running.
      engine.gate.complete();
      await t.pump();
      await t.pump(const Duration(milliseconds: 20));
      expect(find.byType(Skeleton), findsNothing);
      await t.pump(const Duration(milliseconds: 300));
      await t.pump(const Duration(milliseconds: 16));
      expect(_running, 0);
      await t.pump(EditorNotifier.saveDelay);
    });
  }

  testWidgets('changing the body view does not animate', (t) async {
    final a = await launchApp(t, _desktop);
    await openRequest(a, _desktop);
    await t.tap(find.byKey(const Key('send')), warnIfMissed: false);
    await t.pump(const Duration(seconds: 1));
    // A finished animation is only noticed on the next frame.
    await t.pump(const Duration(milliseconds: 16));
    await t.pumpAndSettle();
    final modes = find.byKey(const Key('body-view'));
    expect(
      t.widget<SegmentedButton<String>>(modes).style?.animationDuration,
      Duration.zero,
    );
    for (final label in ['Raw', 'Hex', 'Table', 'Pretty']) {
      await t.tap(find.descendant(of: modes, matching: find.text(label)));
      await t.pump();
      await t.pump(const Duration(milliseconds: 20));
      expect(
        _running,
        lessThanOrEqualTo(1),
        reason: '$label: at most the ripple',
      );
      await t.pump(const Duration(seconds: 1));
      // A finished animation is only noticed on the next frame.
      await t.pump(const Duration(milliseconds: 16));
      expect(_running, 0, reason: '$label settles');
    }
    await t.pump(EditorNotifier.saveDelay);
  });

  testWidgets('a banner appears at once', (t) async {
    await t.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: InlineBanner(tone: BannerTone.warning, child: Text('Careful')),
        ),
      ),
    );
    await t.pump();
    expect(_running, 0);
    expect(find.text('Careful'), findsOneWidget);
  });
}
