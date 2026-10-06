import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:verbnest_app/src/widgets/realtime_dialog.dart';
import 'package:verbnest_http/verbnest_http.dart';

class _Fake implements RealtimeConnection {
  final out = StreamController<RealtimeMessage>.broadcast();
  final sent = <Object>[];
  final _done = Completer<void>();

  @override
  Stream<RealtimeMessage> get messages => out.stream;
  @override
  Future<void> get done => _done.future;
  @override
  bool get canSend => !_done.isCompleted;
  @override
  Future<void> send(Object data) async {
    sent.add(data);
    out.add(RealtimeMessage(direction: RealtimeDirection.sent, data: data));
  }

  @override
  Future<void> close() async {
    if (!_done.isCompleted) _done.complete();
  }
}

Widget _app(
  Future<RealtimeConnection> Function() connect, {
  bool sse = false,
  Future<void> Function(String)? onSave,
}) => MaterialApp(
  home: Scaffold(
    body: RealtimeDialog(
      connect: connect,
      sse: sse,
      title: 'Live',
      onSave: onSave,
    ),
  ),
);

void main() {
  testWidgets('connects, logs, sends and disconnects', (tester) async {
    final fake = _Fake();
    await tester.pumpWidget(_app(() async => fake));
    await tester.tap(find.byKey(const Key('rt-connect')));
    await tester.pump();
    fake.out.add(
      RealtimeMessage(direction: RealtimeDirection.received, data: 'hello'),
    );
    await tester.pump();
    expect(find.textContaining('← hello', findRichText: true), findsOneWidget);

    await tester.enterText(find.byKey(const Key('rt-input')), 'ping');
    await tester.tap(find.byKey(const Key('rt-send')));
    await tester.pump();
    expect(fake.sent, ['ping']);
    expect(find.textContaining('→ ping', findRichText: true), findsOneWidget);

    await tester.tap(find.byKey(const Key('rt-disconnect')));
    await tester.pump();
    expect(find.byKey(const Key('rt-connect')), findsOneWidget);
  });

  testWidgets('shows connect errors; SSE has no message box', (tester) async {
    await tester.pumpWidget(
      _app(() async => throw const FormatException('refused'), sse: true),
    );
    await tester.tap(find.byKey(const Key('rt-connect')));
    await tester.pump();
    expect(find.byKey(const Key('rt-error')), findsOneWidget);
    expect(find.text('refused'), findsOneWidget);
    expect(find.byKey(const Key('rt-input')), findsNothing);
  });

  testWidgets('save hands the transcript to the callback', (tester) async {
    final fake = _Fake();
    String? saved;
    await tester.pumpWidget(
      _app(() async => fake, onSave: (t) async => saved = t),
    );
    expect(
      tester.widget<TextButton>(find.byKey(const Key('rt-save'))).onPressed,
      isNull,
    );
    await tester.tap(find.byKey(const Key('rt-connect')));
    await tester.pump();
    fake.out.add(
      RealtimeMessage(direction: RealtimeDirection.received, data: 'hello'),
    );
    await tester.pump();
    await tester.tap(find.byKey(const Key('rt-save')));
    await tester.pump();
    expect(saved, contains('< hello'));
  });

  testWidgets('hex mode sends bytes and reports bad input', (tester) async {
    final fake = _Fake();
    await tester.pumpWidget(_app(() async => fake));
    await tester.tap(find.byKey(const Key('rt-connect')));
    await tester.pump();
    await tester.tap(find.byKey(const Key('rt-hex')));
    await tester.pump();
    await tester.enterText(find.byKey(const Key('rt-input')), 'zz');
    await tester.tap(find.byKey(const Key('rt-send')));
    await tester.pump();
    expect(find.byKey(const Key('rt-error')), findsOneWidget);
    expect(fake.sent, isEmpty);
    await tester.enterText(find.byKey(const Key('rt-input')), '0a ff');
    await tester.tap(find.byKey(const Key('rt-send')));
    await tester.pump();
    expect(fake.sent.single, [0x0a, 0xff]);
  });

  testWidgets('no save button without a callback', (tester) async {
    await tester.pumpWidget(_app(() async => _Fake()));
    expect(find.byKey(const Key('rt-save')), findsNothing);
  });
}
