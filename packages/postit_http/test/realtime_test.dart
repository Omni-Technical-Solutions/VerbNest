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

    test('reads the retry delay and ignores bad values', () {
      final p = SseParser();
      p.line('retry: 250');
      expect(p.retryMs, 250);
      p.line('retry: soon');
      expect(p.retryMs, 250);
    });

    test('defaults the event name and ignores empty events', () {
      final p = SseParser();
      expect(p.line(''), isNull);
      p.line('data: x');
      expect(p.line('')!.event, 'message');
    });
  });

  test('formatRealtimeLog writes one stamped entry per message', () {
    final text = formatRealtimeLog([
      RealtimeMessage(
        direction: RealtimeDirection.sent,
        data: 'hi',
        at: DateTime.utc(2026, 1, 2, 3, 4, 5),
      ),
      RealtimeMessage(
        direction: RealtimeDirection.received,
        data: 'a\nb',
        event: 'tick',
        at: DateTime.utc(2026, 1, 2, 3, 4, 6),
      ),
      RealtimeMessage(
        direction: RealtimeDirection.system,
        data: [1, 2],
        binary: true,
        at: DateTime.utc(2026, 1, 2, 3, 4, 7),
      ),
    ]);
    expect(
      text,
      '2026-01-02T03:04:05.000Z > hi\n'
      '2026-01-02T03:04:06.000Z < [tick] a\n    b\n'
      '2026-01-02T03:04:07.000Z * <2 bytes binary>\n',
    );
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

    test(
      'reconnects with Last-Event-ID and gives up after the limit',
      () async {
        final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
        addTearDown(() => server.close(force: true));
        final seen = <String?>[];
        server.listen((req) async {
          seen.add(req.headers.value('last-event-id'));
          if (seen.length > 2) {
            req.response
              ..statusCode = 503
              ..close();
            return;
          }
          req.response.headers.contentType = ContentType(
            'text',
            'event-stream',
          );
          req.response.write('id: ${seen.length}\ndata: n${seen.length}\n\n');
          await req.response.close();
        });
        final c = await connectSse(
          Uri.parse('http://127.0.0.1:${server.port}/'),
          reconnect: true,
          maxRetries: 2,
          retryDelay: const Duration(milliseconds: 20),
        );
        final log = await c.messages.toList();
        expect(log.where((m) => m.event != null).map((m) => m.text), [
          'n1',
          'n2',
        ]);
        expect(seen.take(3), [null, '1', '2']);
        expect(
          log
              .where((m) => m.direction == RealtimeDirection.system)
              .map((m) => m.text),
          contains('Gave up after 2 attempts'),
        );
        expect(log.last.text, 'Closed');
      },
    );

    test('closing stops reconnecting', () async {
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      addTearDown(() => server.close(force: true));
      var hits = 0;
      server.listen((req) async {
        hits++;
        req.response.headers.contentType = ContentType('text', 'event-stream');
        req.response.write('data: x\n\n');
        await req.response.close();
      });
      final c = await connectSse(
        Uri.parse('http://127.0.0.1:${server.port}/'),
        reconnect: true,
        retryDelay: const Duration(milliseconds: 500),
      );
      await Future<void>.delayed(const Duration(milliseconds: 100));
      await c.close();
      await c.done;
      await Future<void>.delayed(const Duration(milliseconds: 700));
      expect(hits, 1);
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

  group('proxy', () {
    test('SSE goes through a manual HTTP proxy', () async {
      final proxy = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      addTearDown(() => proxy.close(force: true));
      String? seen;
      proxy.listen((req) async {
        seen = req.headers.host;
        req.response.headers.contentType = ContentType('text', 'event-stream');
        req.response.write('data: via proxy\n\n');
        await req.response.close();
      });
      final c = await connectSse(
        Uri.parse('http://upstream.invalid/stream'),
        settings: HttpSettings(
          proxy: ProxyConfig(
            kind: ProxyKind.http,
            host: '127.0.0.1',
            port: proxy.port,
          ),
        ),
      );
      final log = await c.messages.toList();
      expect(log.any((m) => m.text == 'via proxy'), isTrue);
      expect(seen, 'upstream.invalid');
    });

    test('a SOCKS5 proxy is refused with a clear error', () async {
      expect(
        connectSse(
          Uri.parse('http://upstream.invalid/'),
          settings: HttpSettings(
            proxy: ProxyConfig(
              kind: ProxyKind.socks5,
              host: '127.0.0.1',
              port: 1,
            ),
          ),
        ),
        throwsA(isA<HttpException>()),
      );
    });
  });

  group('GraphQL subscription', () {
    test('acks, subscribes and streams results', () async {
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      addTearDown(() => server.close(force: true));
      String? protocol;
      Object? subscribed;
      server.listen((req) async {
        protocol = req.headers.value('sec-websocket-protocol');
        final ws = await WebSocketTransformer.upgrade(
          req,
          protocolSelector: (p) => p.first,
        );
        ws.listen((d) {
          final m = jsonDecode(d as String) as Map;
          if (m['type'] == 'connection_init') {
            ws.add(jsonEncode({'type': 'connection_ack'}));
          } else if (m['type'] == 'subscribe') {
            subscribed = m['payload'];
            for (var i = 1; i <= 2; i++) {
              ws.add(
                jsonEncode({
                  'id': '1',
                  'type': 'next',
                  'payload': {
                    'data': {'tick': i},
                  },
                }),
              );
            }
            ws.add(jsonEncode({'id': '1', 'type': 'complete'}));
          }
        });
      });
      final c = await connectGraphqlSubscription(
        Uri.parse('ws://127.0.0.1:${server.port}/graphql'),
        {'query': 'subscription { tick }'},
      );
      final log = await c.messages.toList();
      expect(protocol, 'graphql-transport-ws');
      expect(subscribed, {'query': 'subscription { tick }'});
      expect(log.where((m) => m.event == 'next').map((m) => m.text), [
        '{"data":{"tick":1}}',
        '{"data":{"tick":2}}',
      ]);
      expect(log.any((m) => m.text == 'Subscription complete'), isTrue);
    });

    test('fails when the server never acknowledges', () async {
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      addTearDown(() => server.close(force: true));
      server.listen((req) async {
        final ws = await WebSocketTransformer.upgrade(
          req,
          protocolSelector: (p) => p.first,
        );
        ws.listen((_) {});
      });
      expect(
        connectGraphqlSubscription(
          Uri.parse('ws://127.0.0.1:${server.port}/'),
          {'query': 'subscription { x }'},
          settings: const HttpSettings(timeout: Duration(milliseconds: 300)),
        ),
        throwsA(isA<TimeoutException>()),
      );
    });
  });
}
