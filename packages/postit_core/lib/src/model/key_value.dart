/// One row of a params, headers or form table.
class KeyValue {
  const KeyValue({
    required this.key,
    this.value = '',
    this.enabled = true,
    this.description = '',
    this.type = KeyValueType.text,
  });

  final String key;
  final String value;
  final bool enabled;
  final String description;
  final KeyValueType type;

  KeyValue copyWith({
    String? key,
    String? value,
    bool? enabled,
    String? description,
    KeyValueType? type,
  }) => KeyValue(
    key: key ?? this.key,
    value: value ?? this.value,
    enabled: enabled ?? this.enabled,
    description: description ?? this.description,
    type: type ?? this.type,
  );

  Map<String, Object?> toJson() => {
    'key': key,
    'value': value,
    if (!enabled) 'enabled': false,
    if (description.isNotEmpty) 'description': description,
    if (type != KeyValueType.text) 'type': type.name,
  };

  factory KeyValue.fromJson(Map<String, Object?> json) => KeyValue(
    key: json['key'] as String? ?? '',
    value: json['value'] as String? ?? '',
    enabled: json['enabled'] as bool? ?? true,
    description: json['description'] as String? ?? '',
    type: KeyValueType.values.firstWhere(
      (t) => t.name == json['type'],
      orElse: () => KeyValueType.text,
    ),
  );

  static List<KeyValue> listFromJson(Object? json) => [
    for (final e in (json as List<Object?>? ?? const []))
      KeyValue.fromJson((e as Map).cast<String, Object?>()),
  ];

  static List<Map<String, Object?>> listToJson(List<KeyValue> list) => [
    for (final e in list) e.toJson(),
  ];

  @override
  bool operator ==(Object other) =>
      other is KeyValue &&
      other.key == key &&
      other.value == value &&
      other.enabled == enabled &&
      other.description == description &&
      other.type == type;

  @override
  int get hashCode => Object.hash(key, value, enabled, description, type);

  @override
  String toString() => 'KeyValue($key=$value${enabled ? '' : ', off'})';
}

enum KeyValueType { text, file, secret }
