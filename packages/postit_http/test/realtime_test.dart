import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:postit_http/postit_http.dart';
import 'package:test/test.dart';

void main() {
  group('SseParser', () {
    test('assembles multi-line data, event name and id', () {
      final p = SseParser();
      expect(p.line(': comment'), isNull);
      expect(p.line('event: tick'), isNull);
      expect(p.line('id: 7'), isNull);
      expect(p.line('data: a'), isNull);
      expect(p.line('data:b'), isNull);
      final m = p.line('')!;
      expect(m.text, 'a\nb');
      expect(m.event, 'tick');
      expect(m.id, '7');
    });

    test('defaults the event name and ignores empty events', () {
      final p = SseParser();
      expect(p.line(''), isNull);
      p.line('data: x');
      expect(p.line('')!.event, 'message');
    });
  });

  group('WebSocket', () {
    late HttpServer server;
    late Uri url;
    String? seenHeader;

    setUp(() async {
      server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      url = Uri.parse('ws://127.0.0.1:${server.port}/ws');
      server.listen((req) async {
        seenHeader = req.headers.value('x-test');
        final ws = await WebSocketTransformer.upgrade(req);
        ws.listen((d) => ws.add(d is String ? 'echo:$d' : d));
      });
    });
    tearDown(() => server.close(force: true));

    test('sends and receives text and binary, with headers', () async {
      final c = await connectWebSocket(url, headers: [('X-Test', 'yes')]);
      final log = <RealtimeMessage>[];
      c.messages.listen(log.add);
      await c.send('hi');
      await c.send([1, 2, 3]);
      await Future<void>.delayed(const Duration(milliseconds: 200));
      await c.close();
      await c.done;
      expect(seenHeader, 'yes');
      final received = log.where(
        (m) => m.direction == RealtimeDirection.received,
      );
      expect(received.map((m) => m.binary), [false, true]);
      expect(received.first.text, 'echo:hi');
      expect(received.last.data, [1, 2, 3]);
      expect(log.last.text, startsWith('Closed'));
      expect(c.canSend, isFalse);
    });

    test('fails when the server refuses the upgrade', () async {
      final plain = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      plain.listen((r) {
        r.response
          ..statusCode = 200
          ..close();
      });
      addTearDown(() => plain.close(force: true));
      expect(
        connectWebSocket(Uri.parse('ws://127.0.0.1:${plain.port}/')),
        throwsA(isA<WebSocketException>()),
      );
    });
  });

  group('SSE', () {
    test('streams events until the server closes', () async {
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      addTearDown(() => server.close(force: true));
      server.listen((req) async {
        req.response.headers.contentType = ContentType('text', 'event-stream');
        req.response.write('event: a\ndata: 1\n\ndata: 2\n\n');
        await req.response.flush();
        await req.response.close();
      });
      final c = await connectSse(Uri.parse('http://127.0.0.1:${server.port}/'));
      final log = await c.messages.toList();
      expect(
        log.where((m) => m.event != null).map((m) => '${m.event}:${m.text}'),
        ['a:1', 'message:2'],
      );
      expect(c.canSend, isFalse);
      expect(() => c.send('x'), throwsUnsupportedError);
      expect(utf8.encode(log.last.text), isNotEmpty);
    });

    test('non-2xx throws', () async {
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      addTearDown(() => server.close(force: true));
      server.listen((r) {
        r.response
          ..statusCode = 503
          ..close();
      });
      expect(
        connectSse(Uri.parse('http://127.0.0.1:${server.port}/')),
        throwsA(isA<HttpException>()),
      );
    });
  });
}
