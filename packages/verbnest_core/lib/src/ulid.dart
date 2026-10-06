import 'dart:math';

/// Generates ULIDs: 26 chars, lexicographically sortable by creation time.
class Ulid {
  Ulid._();

  static const _alphabet = '0123456789ABCDEFGHJKMNPQRSTVWXYZ';
  static final Random _random = Random.secure();

  static String generate({DateTime? now, Random? random}) {
    final rng = random ?? _random;
    final ms = (now ?? DateTime.now()).millisecondsSinceEpoch;
    final out = StringBuffer();
    for (var i = 9; i >= 0; i--) {
      out.write(_alphabet[(ms >> (5 * i)) & 31]);
    }
    for (var i = 0; i < 16; i++) {
      out.write(_alphabet[rng.nextInt(32)]);
    }
    return out.toString();
  }

  static final _valid = RegExp(r'^[0-9A-HJKMNP-TV-Z]{26}$');

  static bool isValid(String id) => _valid.hasMatch(id);
}
