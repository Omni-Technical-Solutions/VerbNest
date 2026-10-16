import 'dart:async';

import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:verbnest_app/l10n/app_localizations.dart';
import 'package:verbnest_app/src/app.dart';
import 'package:verbnest_app/src/state/editor_state.dart';
import 'package:verbnest_app/src/state/session.dart';
import 'package:verbnest_app/src/theme.dart';
import 'package:verbnest_app/src/widgets/request_editor.dart';
import 'package:verbnest_core/verbnest_core.dart';
import 'package:verbnest_http/verbnest_http.dart';

/// A send that never finishes: enough to tap Send without a network.
class _SlowEngine extends HttpEngine {
  @override
  Future<HttpResponseRecord> send(
    HttpRequestSpec spec, {
    CancelToken? cancel,
  }) => Completer<HttpResponseRecord>().future;
}

void main() {
  group('haptics', () {
    final haptics = <String>[];

    setUp(() {
      haptics.clear();
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(SystemChannels.platform, (call) async {
            if (call.method == 'HapticFeedback.vibrate') {
              haptics.add('${call.arguments}');
            }
            return null;
          });
      addTearDown(
        () => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMethodCallHandler(SystemChannels.platform, null),
      );
    });

    Future<void> pumpEditor(WidgetTester t, TargetPlatform platform) async {
      t.view.physicalSize = const Size(402, 874);
      t.view.devicePixelRatio = 1;
      addTearDown(t.view.reset);
      final s = WorkspaceSession.memory();
      addTearDown(s.close);
      final col = s.repo.createCollection('C');
      final id = s.repo.createRequest(
        col,
        HttpRequestItem(id: '', name: 'R', url: 'https://x.dev'),
      );
      await t.pumpWidget(
        ProviderScope(
          overrides: [
            sessionProvider.overrideWithValue(s),
            engineProvider.overrideWithValue(_SlowEngine()),
          ],
          child: MaterialApp(
            theme: ThemeData(platform: platform),
            localizationsDelegates: [
              AppLocalizations.delegate,
              ...GlobalMaterialLocalizations.delegates,
            ],
            supportedLocales: AppLocalizations.supportedLocales,
            home: Scaffold(body: RequestEditor(requestId: id)),
          ),
        ),
      );
      await t.pump(const Duration(milliseconds: 300));
    }

    testWidgets('sending gives a light tap on a phone', (t) async {
      await pumpEditor(t, TargetPlatform.iOS);
      await t.tap(find.byKey(const Key('send')));
      await t.pump(const Duration(milliseconds: 300));
      expect(haptics, ['HapticFeedbackType.lightImpact']);
    });

    testWidgets('and nothing on desktop', (t) async {
      t.view.physicalSize = const Size(1280, 800);
      await pumpEditor(t, TargetPlatform.macOS);
      await t.tap(find.byKey(const Key('send')));
      await t.pump(const Duration(milliseconds: 300));
      expect(haptics, isEmpty);
    });
  });

  group('Android', () {
    test('every platform changes page with no transition', () {
      // The app has no animation (ADR-020): not the iOS swipe-back slide, the
      // Android predictive back preview or the desktop zoom.
      final builders = buildTheme(Brightness.light)
          .pageTransitionsTheme
          .builders;
      for (final p in TargetPlatform.values) {
        expect(builders.containsKey(p), isTrue, reason: '$p has a builder');
        expect(
          builders[p].runtimeType.toString(),
          '_NoTransitions',
          reason: '$p',
        );
      }
    });

    testWidgets('the navigation bar is transparent, edge to edge', (t) async {
      final s = WorkspaceSession.memory();
      addTearDown(s.close);
      await t.pumpWidget(
        ProviderScope(
          overrides: [sessionProvider.overrideWithValue(s)],
          child: const VerbnestApp(),
        ),
      );
      await t.pump(const Duration(milliseconds: 300));
      final region = t.widget<AnnotatedRegion<SystemUiOverlayStyle>>(
        find.byType(AnnotatedRegion<SystemUiOverlayStyle>).first,
      );
      expect(region.value.systemNavigationBarColor, Colors.transparent);
      expect(region.value.systemNavigationBarContrastEnforced, isFalse);
      expect(region.value.systemNavigationBarIconBrightness, Brightness.dark);
    });
  });
}
