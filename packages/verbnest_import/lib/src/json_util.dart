/// A decoded JSON object.
typedef Json = Map<String, Object?>;

/// [v] as an object, or an empty one when it is not a JSON object.
Json asJsonMap(Object? v) =>
    v is Map ? v.cast<String, Object?>() : <String, Object?>{};

/// [v] as a list, or an empty one when it is not a JSON array.
List<Object?> asJsonList(Object? v) => v is List ? v : const [];

/// [v] when it is a string, else an empty string.
String asJsonString(Object? v) => v is String ? v : '';
