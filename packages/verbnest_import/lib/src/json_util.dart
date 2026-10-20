/// A decoded JSON object.
typedef Json = Map<String, Object?>;

/// [v] as an object, or an empty one when it is not a JSON object.
Json asJsonMap(Object? v) =>
    v is Map ? v.cast<String, Object?>() : <String, Object?>{};

/// [v] as a list, or an empty one when it is not a JSON array.
List<Object?> asJsonList(Object? v) => v is List ? v : const [];

/// [v] when it is a string, else an empty string.
String asJsonString(Object? v) => v is String ? v : '';

const _maxYamlNodes = 500000;
const _maxYamlDepth = 200;

/// Copies parsed YAML into plain maps and lists. Aliases share one node in
/// the parsed tree, so a few lines of aliases can expand to billions of
/// values; this throws [FormatException] past a node or depth limit instead.
Object? plainYaml(Object? root) {
  var nodes = 0;
  Object? walk(Object? v, int depth) {
    if (++nodes > _maxYamlNodes || depth > _maxYamlDepth) {
      throw const FormatException('YAML document is too large or too deep');
    }
    return switch (v) {
      Map() => {
        for (final e in v.entries) '${e.key}': walk(e.value, depth + 1),
      },
      List() => [for (final e in v) walk(e, depth + 1)],
      _ => v,
    };
  }

  return walk(root, 0);
}

/// A JSON scalar as text: null is empty, anything else its string form.
String jsonText(Object? v) => v == null ? '' : '$v';
