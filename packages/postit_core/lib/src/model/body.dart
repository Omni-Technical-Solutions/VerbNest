import 'key_value.dart';

enum RawBodyLanguage {
  json('application/json'),
  xml('application/xml'),
  text('text/plain'),
  html('text/html'),
  javascript('application/javascript');

  const RawBodyLanguage(this.contentType);

  final String contentType;
}

/// Request body (FR-HTTP-006).
sealed class RequestBody {
  const RequestBody();

  String get mode;

  /// Content-Type to add when the user has not set one; null for none.
  String? get defaultContentType;

  Map<String, Object?> toJson();

  factory RequestBody.fromJson(Map<String, Object?>? json) {
    if (json == null) return const NoBody();
    final mode = json['mode'] as String? ?? 'none';
    for (final lang in RawBodyLanguage.values) {
      if (lang.name == mode) {
        return RawBody(lang, json[mode] as String? ?? '');
      }
    }
    return switch (mode) {
      'urlencoded' => UrlEncodedBody(KeyValue.listFromJson(json['urlencoded'])),
      'form' => FormDataBody(KeyValue.listFromJson(json['form'])),
      'binary' => BinaryBody(
        (json['binary'] as Map?)?['attachment'] as String?,
      ),
      _ => const NoBody(),
    };
  }
}

class NoBody extends RequestBody {
  const NoBody();

  @override
  String get mode => 'none';

  @override
  String? get defaultContentType => null;

  @override
  Map<String, Object?> toJson() => {'mode': mode};
}

class RawBody extends RequestBody {
  const RawBody(this.language, this.text);

  final RawBodyLanguage language;
  final String text;

  @override
  String get mode => language.name;

  @override
  String? get defaultContentType => language.contentType;

  @override
  Map<String, Object?> toJson() => {'mode': mode, mode: text};
}

class UrlEncodedBody extends RequestBody {
  const UrlEncodedBody(this.fields);

  final List<KeyValue> fields;

  @override
  String get mode => 'urlencoded';

  @override
  String? get defaultContentType => 'application/x-www-form-urlencoded';

  @override
  Map<String, Object?> toJson() => {
    'mode': mode,
    mode: KeyValue.listToJson(fields),
  };
}

/// multipart/form-data. The boundary, and therefore the full Content-Type,
/// is chosen by the engine when the body is encoded.
class FormDataBody extends RequestBody {
  const FormDataBody(this.fields);

  final List<KeyValue> fields;

  @override
  String get mode => 'form';

  @override
  String? get defaultContentType => null;

  @override
  Map<String, Object?> toJson() => {
    'mode': mode,
    mode: KeyValue.listToJson(fields),
  };
}

class BinaryBody extends RequestBody {
  const BinaryBody(this.attachmentId);

  final String? attachmentId;

  @override
  String get mode => 'binary';

  @override
  String? get defaultContentType => 'application/octet-stream';

  @override
  Map<String, Object?> toJson() => {
    'mode': mode,
    'binary': {'attachment': attachmentId},
  };
}
