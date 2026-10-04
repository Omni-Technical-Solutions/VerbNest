import 'auth.dart';
import 'body.dart';
import 'key_value.dart';

/// Per-request overrides of the workspace HTTP defaults (FR-HTTP-007).
/// Null means "use the default".
class RequestSettings {
  const RequestSettings({
    this.timeoutMs,
    this.verifyTls,
    this.followRedirects,
    this.maxRedirects,
  });

  final int? timeoutMs;
  final bool? verifyTls;
  final bool? followRedirects;
  final int? maxRedirects;

  Map<String, Object?> toJson() => {
    if (timeoutMs != null) 'timeoutMs': timeoutMs,
    if (verifyTls != null) 'verifyTls': verifyTls,
    if (followRedirects != null) 'followRedirects': followRedirects,
    if (maxRedirects != null) 'maxRedirects': maxRedirects,
  };

  factory RequestSettings.fromJson(Map<String, Object?>? json) =>
      RequestSettings(
        timeoutMs: json?['timeoutMs'] as int?,
        verifyTls: json?['verifyTls'] as bool?,
        followRedirects: json?['followRedirects'] as bool?,
        maxRedirects: json?['maxRedirects'] as int?,
      );
}

class Scripts {
  const Scripts({this.pre = '', this.post = ''});

  final String pre;
  final String post;

  bool get isEmpty => pre.isEmpty && post.isEmpty;

  Map<String, Object?> toJson() => {
    if (pre.isNotEmpty) 'pre': pre,
    if (post.isNotEmpty) 'post': post,
  };

  factory Scripts.fromJson(Map<String, Object?>? json) => Scripts(
    pre: json?['pre'] as String? ?? '',
    post: json?['post'] as String? ?? '',
  );
}

/// An HTTP request as stored in the workspace (data-model §2.2).
///
/// [extra] carries keys this version does not know, so a workspace written by
/// a newer version survives a load/save cycle.
class HttpRequestItem {
  const HttpRequestItem({
    required this.id,
    required this.name,
    this.method = 'GET',
    this.url = '',
    this.params = const [],
    this.pathVars = const [],
    this.headers = const [],
    this.body = const NoBody(),
    this.auth = const InheritAuth(),
    this.settings = const RequestSettings(),
    this.scripts = const Scripts(),
    this.description = '',
    this.extra = const {},
  });

  final String id;
  final String name;
  final String method;
  final String url;
  final List<KeyValue> params;
  final List<KeyValue> pathVars;
  final List<KeyValue> headers;
  final RequestBody body;
  final Auth auth;
  final RequestSettings settings;
  final Scripts scripts;
  final String description;
  final Map<String, Object?> extra;

  HttpRequestItem copyWith({
    String? name,
    String? method,
    String? url,
    List<KeyValue>? params,
    List<KeyValue>? pathVars,
    List<KeyValue>? headers,
    RequestBody? body,
    Auth? auth,
    RequestSettings? settings,
    Scripts? scripts,
    String? description,
  }) => HttpRequestItem(
    id: id,
    name: name ?? this.name,
    method: method ?? this.method,
    url: url ?? this.url,
    params: params ?? this.params,
    pathVars: pathVars ?? this.pathVars,
    headers: headers ?? this.headers,
    body: body ?? this.body,
    auth: auth ?? this.auth,
    settings: settings ?? this.settings,
    scripts: scripts ?? this.scripts,
    description: description ?? this.description,
    extra: extra,
  );

  /// The type-specific document stored in `node.data`. Name, description,
  /// auth and scripts have their own columns.
  Map<String, Object?> toData() => {
    ...extra,
    'method': method,
    'url': url,
    'params': KeyValue.listToJson(params),
    'pathVars': KeyValue.listToJson(pathVars),
    'headers': KeyValue.listToJson(headers),
    'body': body.toJson(),
    'settings': settings.toJson(),
  };

  static const _knownDataKeys = {
    'method',
    'url',
    'params',
    'pathVars',
    'headers',
    'body',
    'settings',
  };

  factory HttpRequestItem.fromData({
    required String id,
    required String name,
    required Map<String, Object?> data,
    Map<String, Object?>? auth,
    Map<String, Object?>? scripts,
    String description = '',
  }) => HttpRequestItem(
    id: id,
    name: name,
    method: data['method'] as String? ?? 'GET',
    url: data['url'] as String? ?? '',
    params: KeyValue.listFromJson(data['params']),
    pathVars: KeyValue.listFromJson(data['pathVars']),
    headers: KeyValue.listFromJson(data['headers']),
    body: RequestBody.fromJson((data['body'] as Map?)?.cast<String, Object?>()),
    auth: Auth.fromJson(auth),
    settings: RequestSettings.fromJson(
      (data['settings'] as Map?)?.cast<String, Object?>(),
    ),
    scripts: Scripts.fromJson(scripts),
    description: description,
    extra: {
      for (final e in data.entries)
        if (!_knownDataKeys.contains(e.key)) e.key: e.value,
    },
  );
}
