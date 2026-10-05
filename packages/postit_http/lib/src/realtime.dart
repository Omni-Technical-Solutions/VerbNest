import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'models.dart';

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
      case 'id':
        if (!value.contains('\u0000')) {
          _id = value;
          lastId = value;
        }
    }
    return null;
  }
}

HttpClient _client(HttpSettings s, Uri url) {
  final client = HttpClient(
    context: s.tls == null || s.tls!.isEmpty
        ? null
        : s.tls!.contextFor(url.host),
  );
  if (!s.verifyTls) client.badCertificateCallback = (_, _, _) => true;
  client.connectionTimeout = s.timeout;
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
      (d) => _out.add(
        RealtimeMessage(
          direction: RealtimeDirection.received,
          data: d is String ? d : Uint8List.fromList(d as List<int>),
          binary: d is! String,
        ),
      ),
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
Future<RealtimeConnection> connectSse(
  Uri url, {
  List<Header> headers = const [],
  String method = 'GET',
  List<int>? body,
  HttpSettings settings = const HttpSettings(),
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
    if (body != null && body.isNotEmpty) req.add(body);
    final res = await req.close().timeout(settings.timeout);
    if (res.statusCode < 200 || res.statusCode > 299) {
      await res.drain<void>();
      throw HttpException('SSE endpoint answered ${res.statusCode}', uri: url);
    }
    return _SseConnection(res, client);
  } catch (_) {
    client.close(force: true);
    rethrow;
  }
}

class _SseConnection implements RealtimeConnection {
  _SseConnection(HttpClientResponse res, this._client) {
    _out.add(
      RealtimeMessage(
        direction: RealtimeDirection.system,
        data: 'Connected (${res.statusCode})',
      ),
    );
    final parser = SseParser();
    _sub = res
        .cast<List<int>>()
        .transform(utf8.decoder)
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
  late final StreamSubscription<String> _sub;
  final _out = StreamController<RealtimeMessage>.broadcast();
  final _done = Completer<void>();

  void _finish() {
    if (_done.isCompleted) return;
    _out.add(
      RealtimeMessage(direction: RealtimeDirection.system, data: 'Closed'),
    );
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
