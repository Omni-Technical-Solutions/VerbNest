import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'models.dart';
import 'proxy.dart';

enum RealtimeDirection { sent, received, system }

/// One entry in a WebSocket or SSE log.
class RealtimeMessage {
  RealtimeMessage({
    required this.direction,
    required this.data,
    DateTime? at,
    this.binary = false,
    this.event,
    this.id,
  }) : at = at ?? DateTime.now();

  final RealtimeDirection direction;

  /// Text payload, or the raw bytes for binary frames.
  final Object data;
  final DateTime at;
  final bool binary;

  /// SSE `event:` name and `id:` value.
  final String? event;
  final String? id;

  String get text => data is String
      ? data as String
      : '<${(data as List<int>).length} bytes binary>';
}

/// Bytes from hex text such as `de ad BE:EF` or `0xdeadbeef`. Spaces, colons,
/// commas and a `0x` prefix are ignored. Throws [FormatException] on other
/// characters or an odd number of digits.
Uint8List parseHexBytes(String text) {
  final clean = text
      .replaceAll(RegExp(r'0x', caseSensitive: false), '')
      .replaceAll(RegExp(r'[\s:,]'), '');
  if (!RegExp(r'^[0-9a-fA-F]*$').hasMatch(clean)) {
    throw const FormatException('Hex bytes may only hold 0-9 and a-f');
  }
  if (clean.length.isOdd) {
    throw const FormatException('Hex bytes need an even number of digits');
  }
  return Uint8List.fromList([
    for (var i = 0; i < clean.length; i += 2)
      int.parse(clean.substring(i, i + 2), radix: 16),
  ]);
}

/// Plain-text transcript of a live session, one entry per line with an
/// ISO-8601 UTC time. Direction is `>` sent, `<` received, `*` notice.
String formatRealtimeLog(Iterable<RealtimeMessage> messages) {
  final b = StringBuffer();
  for (final m in messages) {
    final mark = switch (m.direction) {
      RealtimeDirection.sent => '>',
      RealtimeDirection.received => '<',
      RealtimeDirection.system => '*',
    };
    final event = m.event == null || m.event == 'message'
        ? ''
        : '[${m.event}] ';
    final text = m.text.replaceAll('\n', '\n    ');
    b.writeln('${m.at.toUtc().toIso8601String()} $mark $event$text');
  }
  return b.toString();
}

/// A long-lived connection that streams messages (architecture ADR-009).
/// WebSocket and SSE share this shape so the UI and CLI need one code path.
abstract class RealtimeConnection {
  Stream<RealtimeMessage> get messages;

  /// Completes when the connection ends; errors surface as system messages.
  Future<void> get done;

  bool get canSend;

  Future<void> send(Object data);

  Future<void> close();
}

/// Reassembles SSE fields from a stream of decoded text lines.
class SseParser {
  String? _event;
  String? _id;
  final _data = <String>[];

  /// Last event id seen, for `Last-Event-ID` on reconnect.
  String? lastId;

  /// Reconnection delay the server asked for with `retry:`, in milliseconds.
  int? retryMs;

  /// Feeds one line (without terminator); returns an event when a blank
  /// line completes one.
  RealtimeMessage? line(String line) {
    if (line.isEmpty) {
      if (_data.isEmpty) {
        _event = null;
        return null;
      }
      final m = RealtimeMessage(
        direction: RealtimeDirection.received,
        data: _data.join('\n'),
        event: _event ?? 'message',
        id: _id ?? lastId,
      );
      _data.clear();
      _event = null;
      return m;
    }
    if (line.startsWith(':')) return null;
    final i = line.indexOf(':');
    final field = i < 0 ? line : line.substring(0, i);
    var value = i < 0 ? '' : line.substring(i + 1);
    if (value.startsWith(' ')) value = value.substring(1);
    switch (field) {
      case 'data':
        _data.add(value);
      case 'event':
        _event = value;
      case 'retry':
        if (RegExp(r'^\d+$').hasMatch(value)) retryMs = int.parse(value);
      case 'id':
        if (!value.contains('\u0000')) {
          _id = value;
          lastId = value;
        }
    }
    return null;
  }
}

HttpClient _client(
  HttpSettings s,
  Uri url, [
  Map<String, String>? environment,
]) {
  final client = HttpClient(
    context: s.tls == null || s.tls!.isEmpty
        ? null
        : s.tls!.contextFor(url.host),
  );
  if (!s.verifyTls) client.badCertificateCallback = (_, _, _) => true;
  client.connectionTimeout = s.timeout;
  final manual = s.proxy;
  final proxy = manual != null
      ? (manual.bypasses(url.host) ? null : manual)
      : (s.useSystemProxy
            ? ProxyConfig.fromEnvironment(
                url,
                environment ?? Platform.environment,
              )
            : null);
  if (proxy != null) {
    if (proxy.kind != ProxyKind.http) {
      client.close(force: true);
      throw HttpException(
        'SOCKS5 proxies are not supported for WebSocket and SSE',
        uri: url,
      );
    }
    client.findProxy = (_) => 'PROXY ${proxy.host}:${proxy.port}';
    if (proxy.hasAuth) {
      client.addProxyCredentials(
        proxy.host,
        proxy.port,
        '',
        HttpClientBasicCredentials(proxy.username, proxy.password),
      );
    }
  }
  return client;
}

/// Opens a WebSocket. `ws`/`wss` map to `http`/`https` for the handshake.
Future<RealtimeConnection> connectWebSocket(
  Uri url, {
  List<Header> headers = const [],
  List<String> protocols = const [],
  HttpSettings settings = const HttpSettings(),
}) async {
  final client = _client(settings, url);
  final target = url.replace(
    scheme: url.scheme == 'wss' || url.scheme == 'https' ? 'https' : 'http',
  );
  final WebSocket socket;
  try {
    socket = await WebSocket.connect(
      target.toString().replaceFirst(RegExp('^http'), 'ws'),
      protocols: protocols.isEmpty ? null : protocols,
      headers: {for (final (k, v) in headers) k: v},
      customClient: client,
    ).timeout(settings.timeout);
  } catch (_) {
    client.close(force: true);
    rethrow;
  }
  return _WebSocketConnection(socket, client);
}

class _WebSocketConnection implements RealtimeConnection {
  _WebSocketConnection(this._socket, this._client) {
    _out.add(
      RealtimeMessage(
        direction: RealtimeDirection.system,
        data:
            'Connected${_socket.protocol == null ? '' : ' '
                      '(${_socket.protocol})'}',
      ),
    );
    _socket.listen(
      (d) {
        final size = d is String ? d.length : (d as List<int>).length;
        if (size > maxRealtimeMessageBytes) {
          _out.add(
            RealtimeMessage(
              direction: RealtimeDirection.system,
              data: 'Message of $size bytes dropped: too large',
            ),
          );
          _socket.close(1009, 'Message too big');
          return;
        }
        _out.add(
          RealtimeMessage(
            direction: RealtimeDirection.received,
            data: d is String ? d : Uint8List.fromList(d as List<int>),
            binary: d is! String,
          ),
        );
      },
      onError: (Object e) => _out.add(
        RealtimeMessage(direction: RealtimeDirection.system, data: '$e'),
      ),
      onDone: () {
        _closed = true;
        _out.add(
          RealtimeMessage(
            direction: RealtimeDirection.system,
            data:
                'Closed (${_socket.closeCode ?? '-'}'
                '${_socket.closeReason == null || _socket.closeReason!.isEmpty ? '' : ' ${_socket.closeReason}'})',
          ),
        );
        _out.close();
        _client.close(force: true);
        _done.complete();
      },
    );
  }

  final WebSocket _socket;
  final HttpClient _client;
  final _out = StreamController<RealtimeMessage>.broadcast();
  final _done = Completer<void>();
  bool _closed = false;

  @override
  Stream<RealtimeMessage> get messages => _out.stream;

  @override
  Future<void> get done => _done.future;

  @override
  bool get canSend => !_closed;

  @override
  Future<void> send(Object data) async {
    if (_closed) throw StateError('WebSocket is closed');
    _socket.add(data);
    _out.add(
      RealtimeMessage(
        direction: RealtimeDirection.sent,
        data: data is List<int> ? Uint8List.fromList(data) : data,
        binary: data is! String,
      ),
    );
  }

  @override
  Future<void> close() => _socket.close(WebSocketStatus.normalClosure);
}

/// Opens an SSE stream. Non-2xx responses and wrong content types throw.
///
/// With [reconnect], a stream that ends without [RealtimeConnection.close]
/// is reopened after the server's `retry:` delay (3 s by default, at most
/// 60 s) with `Last-Event-ID`, up to [maxRetries] failed attempts in a row.
/// [retryDelay] replaces the delay for tests.
Future<RealtimeConnection> connectSse(
  Uri url, {
  List<Header> headers = const [],
  String method = 'GET',
  List<int>? body,
  HttpSettings settings = const HttpSettings(),
  bool reconnect = false,
  int maxRetries = 5,
  Duration? retryDelay,
}) async {
  Future<_SseConnection> open(String? lastId) => _openSse(
    url,
    headers: headers,
    method: method,
    body: body,
    settings: settings,
    lastEventId: lastId,
    quiet: reconnect,
  );
  final first = await open(null);
  if (!reconnect) return first;
  return _ReconnectingSse(first, open, maxRetries, retryDelay);
}

Future<_SseConnection> _openSse(
  Uri url, {
  required List<Header> headers,
  required String method,
  required List<int>? body,
  required HttpSettings settings,
  required String? lastEventId,
  required bool quiet,
}) async {
  final client = _client(settings, url);
  try {
    final req = await client.openUrl(method, url);
    req.followRedirects = settings.followRedirects;
    req.headers.set('Accept', 'text/event-stream');
    req.headers.set('Cache-Control', 'no-cache');
    for (final (k, v) in headers) {
      req.headers.set(k, v);
    }
    if (lastEventId != null) req.headers.set('Last-Event-ID', lastEventId);
    if (body != null && body.isNotEmpty) req.add(body);
    final res = await req.close().timeout(settings.timeout);
    if (res.statusCode < 200 || res.statusCode > 299) {
      await res.drain<void>();
      throw HttpException('SSE endpoint answered ${res.statusCode}', uri: url);
    }
    return _SseConnection(res, client, lastEventId, quiet: quiet);
  } catch (_) {
    client.close(force: true);
    rethrow;
  }
}

class _SseConnection implements RealtimeConnection {
  _SseConnection(
    HttpClientResponse res,
    this._client,
    String? lastId, {
    this.quiet = false,
  }) {
    _out.add(
      RealtimeMessage(
        direction: RealtimeDirection.system,
        data: 'Connected (${res.statusCode})',
      ),
    );
    parser.lastId = lastId;
    var lineBytes = 0;
    _sub = res
        .cast<List<int>>()
        .map((chunk) {
          // LineSplitter buffers a whole line, so cap lines before it.
          for (final b in chunk) {
            lineBytes = b == 10 ? 0 : lineBytes + 1;
          }
          if (lineBytes > maxRealtimeMessageBytes) {
            throw const FormatException('Event line is too large');
          }
          return chunk;
        })
        // A stray invalid byte becomes U+FFFD; it must not end the stream.
        .transform(const Utf8Decoder(allowMalformed: true))
        .transform(const LineSplitter())
        .listen(
          (l) {
            final m = parser.line(l);
            if (m != null) _out.add(m);
          },
          onError: (Object e) => _out.add(
            RealtimeMessage(direction: RealtimeDirection.system, data: '$e'),
          ),
          onDone: _finish,
          cancelOnError: false,
        );
  }

  final HttpClient _client;
  final parser = SseParser();

  /// Quiet connections leave the "Closed" notice to the reconnect wrapper.
  final bool quiet;
  late final StreamSubscription<String> _sub;
  final _out = StreamController<RealtimeMessage>.broadcast();
  final _done = Completer<void>();

  void _finish() {
    if (_done.isCompleted) return;
    if (!quiet) {
      _out.add(
        RealtimeMessage(direction: RealtimeDirection.system, data: 'Closed'),
      );
    }
    _out.close();
    _client.close(force: true);
    _done.complete();
  }

  @override
  Stream<RealtimeMessage> get messages => _out.stream;

  @override
  Future<void> get done => _done.future;

  @override
  bool get canSend => false;

  @override
  Future<void> send(Object data) =>
      throw UnsupportedError('SSE connections are receive-only');

  @override
  Future<void> close() async {
    await _sub.cancel();
    _finish();
  }
}

class _ReconnectingSse implements RealtimeConnection {
  _ReconnectingSse(
    _SseConnection first,
    this._open,
    this._maxRetries,
    this._retryDelay,
  ) {
    _run(first);
  }

  final Future<_SseConnection> Function(String? lastId) _open;
  final int _maxRetries;
  final Duration? _retryDelay;
  final _out = StreamController<RealtimeMessage>.broadcast();
  final _done = Completer<void>();
  _SseConnection? _current;
  bool _closed = false;

  void _say(String text) => _out.add(
    RealtimeMessage(direction: RealtimeDirection.system, data: text),
  );

  Future<void> _run(_SseConnection first) async {
    var conn = first;
    var failures = 0;
    while (true) {
      _current = conn;
      final sub = conn.messages.listen(_out.add);
      await conn.done;
      await sub.cancel();
      if (_closed) break;
      var delay =
          _retryDelay ?? Duration(milliseconds: conn.parser.retryMs ?? 3000);
      if (delay > const Duration(seconds: 60)) {
        delay = const Duration(seconds: 60);
      }
      final lastId = conn.parser.lastId;
      _SseConnection? next;
      while (next == null && !_closed) {
        if (failures >= _maxRetries) {
          _say('Gave up after $_maxRetries attempts');
          return _end();
        }
        _say('Disconnected; reconnecting in ${delay.inMilliseconds} ms');
        await Future<void>.delayed(delay);
        if (_closed) break;
        try {
          next = await _open(lastId);
          failures = 0;
        } on Object catch (e) {
          failures++;
          _say('Reconnect failed: $e');
        }
      }
      if (next == null) break;
      conn = next;
    }
    _end();
  }

  void _end() {
    if (_done.isCompleted) return;
    _say('Closed');
    _out.close();
    _done.complete();
  }

  @override
  Stream<RealtimeMessage> get messages => _out.stream;

  @override
  Future<void> get done => _done.future;

  @override
  bool get canSend => false;

  @override
  Future<void> send(Object data) =>
      throw UnsupportedError('SSE connections are receive-only');

  @override
  Future<void> close() async {
    _closed = true;
    await _current?.close();
    _end();
  }
}

/// Subscribes over the `graphql-transport-ws` protocol. [payload] is the
/// GraphQL request body (`query`, `variables`, `operationName`). Each `next`
/// message becomes a received message holding the result JSON; `error` and
/// `complete` end the stream with a system message.
Future<RealtimeConnection> connectGraphqlSubscription(
  Uri url,
  Map<String, Object?> payload, {
  List<Header> headers = const [],
  Map<String, Object?> connectionParams = const {},
  HttpSettings settings = const HttpSettings(),
}) async {
  final inner = await connectWebSocket(
    url,
    headers: headers,
    protocols: const ['graphql-transport-ws'],
    settings: settings,
  );
  final ack = Completer<void>();
  final out = StreamController<RealtimeMessage>.broadcast();
  final done = Completer<void>();

  void system(String text) =>
      out.add(RealtimeMessage(direction: RealtimeDirection.system, data: text));

  inner.messages.listen((m) {
    if (m.direction == RealtimeDirection.system) {
      system(m.text);
      return;
    }
    if (m.direction != RealtimeDirection.received || m.binary) return;
    final Object? msg;
    try {
      msg = jsonDecode(m.text);
    } on FormatException {
      system('Unreadable message: ${m.text}');
      return;
    }
    if (msg is! Map) return;
    switch (msg['type']) {
      case 'connection_ack':
        if (!ack.isCompleted) ack.complete();
      case 'next':
        out.add(
          RealtimeMessage(
            direction: RealtimeDirection.received,
            data: jsonEncode(msg['payload']),
            event: 'next',
          ),
        );
      case 'error':
        system('Subscription error: ${jsonEncode(msg['payload'])}');
        unawaited(inner.close());
      case 'complete':
        system('Subscription complete');
        unawaited(inner.close());
      case 'ping':
        unawaited(inner.send(jsonEncode({'type': 'pong'})));
    }
  });
  unawaited(
    inner.done.whenComplete(() {
      if (!ack.isCompleted) {
        ack.completeError(
          const WebSocketException('Closed before connection_ack'),
        );
      }
      out.close();
      done.complete();
    }),
  );

  await inner.send(
    jsonEncode({
      'type': 'connection_init',
      if (connectionParams.isNotEmpty) 'payload': connectionParams,
    }),
  );
  try {
    await ack.future.timeout(settings.timeout);
  } catch (_) {
    await inner.close();
    rethrow;
  }
  await inner.send(
    jsonEncode({'id': '1', 'type': 'subscribe', 'payload': payload}),
  );
  return _GraphqlWs(inner, out, done);
}

class _GraphqlWs implements RealtimeConnection {
  _GraphqlWs(this._inner, this._out, this._done);

  final RealtimeConnection _inner;
  final StreamController<RealtimeMessage> _out;
  final Completer<void> _done;

  @override
  Stream<RealtimeMessage> get messages => _out.stream;

  @override
  Future<void> get done => _done.future;

  @override
  bool get canSend => false;

  @override
  Future<void> send(Object data) =>
      throw UnsupportedError('Subscriptions are receive-only');

  @override
  Future<void> close() async {
    if (_inner.canSend) {
      await _inner.send(jsonEncode({'id': '1', 'type': 'complete'}));
    }
    await _inner.close();
  }
}

/// Largest single WebSocket message or SSE line kept in memory.
const maxRealtimeMessageBytes = 16 * 1024 * 1024;
