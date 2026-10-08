import 'package:sqlite3/sqlite3.dart';

import 'errors.dart';

/// Typed column reads. A stored value of the wrong type (a hand-edited or
/// corrupted workspace file) fails with a [StorageFormatError] that names the
/// column, not an anonymous cast error.
extension TypedRow on Row {
  T _get<T>(String column) {
    final v = this[column];
    if (v is T) return v;
    throw StorageFormatError(
      'Column "$column" holds ${v.runtimeType}, expected $T',
    );
  }

  String str(String column) => _get<String>(column);
  String? strOrNull(String column) => _get<String?>(column);
  int integer(String column) => _get<int>(column);
  int? integerOrNull(String column) => _get<int?>(column);
  bool flag(String column) => integer(column) != 0;
}
