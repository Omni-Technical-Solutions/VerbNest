import 'dart:math';

/// Generates `{{$name}}` values. A fresh value is produced on every call so
/// each occurrence in a request differs (FR-VAR-005, data-model §5.4).
class DynamicVariables {
  DynamicVariables({Random? random, DateTime Function()? clock})
    : _random = random ?? Random.secure(),
      _clock = clock ?? DateTime.now;

  final Random _random;
  final DateTime Function() _clock;

  static const _firstNames = [
    'Alex',
    'Sam',
    'Jordan',
    'Taylor',
    'Morgan',
    'Casey',
    'Riley',
    'Jamie',
  ];

  /// Returns the value for [name] (including the leading `$`), or null when
  /// the name is not a known dynamic variable.
  String? generate(String name) => switch (name) {
    r'$guid' || r'$randomUUID' => _uuidV4(),
    r'$timestamp' => '${_clock().millisecondsSinceEpoch ~/ 1000}',
    r'$isoTimestamp' => _clock().toUtc().toIso8601String(),
    r'$randomInt' => '${_random.nextInt(1001)}',
    r'$randomFirstName' => _firstNames[_random.nextInt(_firstNames.length)],
    r'$randomEmail' => _email(),
    _ => null,
  };

  String _email() {
    final name = _firstNames[_random.nextInt(_firstNames.length)];
    return '${name.toLowerCase()}${_random.nextInt(10000)}@example.com';
  }

  String _uuidV4() {
    final bytes = List<int>.generate(16, (_) => _random.nextInt(256));
    bytes[6] = (bytes[6] & 0x0f) | 0x40;
    bytes[8] = (bytes[8] & 0x3f) | 0x80;
    final hex = bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
    return '${hex.substring(0, 8)}-${hex.substring(8, 12)}-'
        '${hex.substring(12, 16)}-${hex.substring(16, 20)}-${hex.substring(20)}';
  }
}
