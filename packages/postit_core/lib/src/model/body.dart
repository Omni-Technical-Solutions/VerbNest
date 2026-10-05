import 'dart:convert';

import '../graphql/payload.dart';
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
      'graphql' => GraphqlBody.fromJson(json['graphql']),
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

/// A GraphQL operation sent as a JSON POST body (FR-GQL-001). All three
/// fields may hold `{{variables}}`; they are resolved before the payload is
/// built, so [variables] only has to be valid JSON after resolution.
class GraphqlBody extends RequestBody {
  const GraphqlBody({
    this.query = '',
    this.variables = '',
    this.operationName = '',
    this.persisted = false,
  });

  final String query;

  /// Send an Apollo persisted-query hash instead of the document, falling
  /// back to the full query when the server has not seen it yet.
  final bool persisted;

  /// JSON object text; empty means no variables.
  final String variables;
  final String operationName;

  GraphqlBody copyWith({
    String? query,
    String? variables,
    String? operationName,
    bool? persisted,
  }) => GraphqlBody(
    persisted: persisted ?? this.persisted,
    query: query ?? this.query,
    variables: variables ?? this.variables,
    operationName: operationName ?? this.operationName,
  );

  /// The JSON request body. [resolve] replaces `{{variables}}` in each field
  /// first. With [lenient], variables that are not valid JSON are left out
  /// instead of throwing; exports use this so they never fail. With
  /// [hashOnly] and [persisted], the query text is replaced by its hash.
  String toPayload({
    String Function(String)? resolve,
    bool lenient = false,
    bool hashOnly = false,
  }) {
    String r(String s) => resolve == null ? s : resolve(s);
    try {
      return graphqlPayload(
        query: r(query),
        variables: r(variables),
        operationName: r(operationName),
        persisted: persisted,
        omitQuery: hashOnly,
      );
    } on FormatException {
      if (!lenient) rethrow;
      return graphqlPayload(
        query: r(query),
        operationName: r(operationName),
        persisted: persisted,
        omitQuery: hashOnly,
      );
    }
  }

  /// A GET carries the operation in the URL, as the GraphQL-over-HTTP spec
  /// describes, because a GET has no body.
  bool sentInUrl(String method) => method.trim().toUpperCase() == 'GET';

  /// `query=...&variables=...&operationName=...`, percent-encoded, ready to
  /// append to a URL. Same [resolve] and [lenient] rules as [toPayload].
  String toQueryString({
    String Function(String)? resolve,
    bool lenient = false,
    bool hashOnly = false,
  }) {
    final payload = jsonDecode(
      toPayload(resolve: resolve, lenient: lenient, hashOnly: hashOnly),
    ) as Map<String, Object?>;
    return [
      for (final e in payload.entries)
        '${Uri.encodeQueryComponent(e.key)}='
            '${Uri.encodeQueryComponent(e.value is String ? e.value as String : jsonEncode(e.value))}',
    ].join('&');
  }

  @override
  String get mode => 'graphql';

  @override
  String? get defaultContentType => 'application/json';

  @override
  Map<String, Object?> toJson() => {
    'mode': mode,
    mode: {
      if (query.isNotEmpty) 'query': query,
      if (variables.isNotEmpty) 'variables': variables,
      if (operationName.isNotEmpty) 'operationName': operationName,
      if (persisted) 'persisted': true,
    },
  };

  factory GraphqlBody.fromJson(Object? json) {
    final m = json is Map ? json : const {};
    return GraphqlBody(
      query: m['query'] as String? ?? '',
      variables: m['variables'] as String? ?? '',
      operationName: m['operationName'] as String? ?? '',
      persisted: m['persisted'] == true,
    );
  }
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
