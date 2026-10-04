import 'dart:async';
import 'dart:typed_data';

/// Pull-style reader over a byte stream with one-chunk lookahead.
class ByteReader {
  ByteReader(Stream<List<int>> stream) : _it = StreamIterator(stream);

  final StreamIterator<List<int>> _it;
  Uint8List _pending = Uint8List(0);
  bool _done = false;

  Future<bool> _fill() async {
    if (_done) return false;
    if (!await _it.moveNext()) {
      _done = true;
      return false;
    }
    _pending = Uint8List.fromList(_it.current);
    return true;
  }

  Uint8List _take(int n) {
    final out = _pending.sublist(0, n);
    _pending = _pending.sublist(n);
    return out;
  }

  /// Reads up to and including the first `\r\n\r\n`. Returns the bytes
  /// before the terminator, or null if the stream ended first.
  Future<Uint8List?> readHead() async {
    final all = BytesBuilder();
    var matched = 0;
    const term = [13, 10, 13, 10];
    while (true) {
      if (_pending.isEmpty && !await _fill()) return null;
      for (var i = 0; i < _pending.length; i++) {
        matched = _pending[i] == term[matched] ? matched + 1 : (_pending[i] == 13 ? 1 : 0);
        if (matched == 4) {
          all.add(_take(i + 1));
          final bytes = all.toBytes();
          return Uint8List.sublistView(bytes, 0, bytes.length - 4);
        }
      }
      all.add(_take(_pending.length));
    }
  }

  /// Reads one CRLF-terminated line (without the CRLF).
  Future<String> readLine() async {
    final line = BytesBuilder();
    while (true) {
      if (_pending.isEmpty && !await _fill()) {
        throw const FormatException('Connection closed mid-line');
      }
      final i = _pending.indexOf(10);
      if (i == -1) {
        line.add(_take(_pending.length));
        continue;
      }
      line.add(_take(i + 1));
      final bytes = line.toBytes();
      final end = bytes.length >= 2 && bytes[bytes.length - 2] == 13
          ? bytes.length - 2
          : bytes.length - 1;
      return String.fromCharCodes(bytes.sublist(0, end));
    }
  }

  /// Reads exactly [n] bytes or throws if the stream ends early.
  Future<Uint8List> readExact(int n) async {
    final out = BytesBuilder(copy: false);
    var remaining = n;
    while (remaining > 0) {
      if (_pending.isEmpty && !await _fill()) {
        throw const FormatException('Connection closed mid-body');
      }
      final take = remaining < _pending.length ? remaining : _pending.length;
      out.add(_take(take));
      remaining -= take;
    }
    return out.toBytes();
  }

  Future<Uint8List> readToEnd() async {
    final out = BytesBuilder(copy: false);
    while (true) {
      if (_pending.isNotEmpty) out.add(_take(_pending.length));
      if (!await _fill()) return out.toBytes();
    }
  }

  Future<void> cancel() => _it.cancel();
}
