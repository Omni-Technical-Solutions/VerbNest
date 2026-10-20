import 'package:flutter_riverpod/flutter_riverpod.dart';

/// One network event, with secrets already masked (FR-HIS-004).
class ConsoleEntry {
  const ConsoleEntry({
    required this.at,
    required this.method,
    required this.url,
    required this.sentHead,
    this.status,
    this.ms,
    this.responseHead,
    this.error,
  });

  final DateTime at;
  final String method;
  final String url;
  final String sentHead;
  final int? status;
  final int? ms;
  final String? responseHead;
  final String? error;
}

/// The last requests sent in this session. It is memory only and is cleared
/// when the app closes or the workspace is switched.
class ConsoleLog extends Notifier<List<ConsoleEntry>> {
  static const capacity = 200;

  @override
  List<ConsoleEntry> build() => const [];

  void add(ConsoleEntry e) {
    final next = [e, ...state];
    state = next.length > capacity ? next.sublist(0, capacity) : next;
  }

  final _warned = <String>{};

  /// Adds [e] unless [key] was already warned about in this session, so a
  /// problem that repeats on every request shows up once.
  void warnOnce(String key, ConsoleEntry e) {
    if (_warned.add(key)) add(e);
  }

  void clear() {
    _warned.clear();
    state = const [];
  }
}

final consoleLogProvider = NotifierProvider<ConsoleLog, List<ConsoleEntry>>(
  ConsoleLog.new,
);
