import 'package:verbnest_core/verbnest_core.dart';

import 'json_util.dart';

// ---- environments ---------------------------------------------------------

/// Whether [json] is a Postman environment or globals export.
bool looksLikePostmanEnvironment(Object? json) {
  final m = asJsonMap(json);
  return m['values'] is List && !m.containsKey('info');
}

/// Imports a Postman environment or globals file. `secret` entries become
/// secret variables.
({String name, List<Variable> variables}) importPostmanEnvironment(
  Object? json,
) {
  final m = asJsonMap(json);
  if (!looksLikePostmanEnvironment(m)) {
    throw const FormatException('Not a Postman environment');
  }
  return (
    name: asJsonString(m['name']).isEmpty
        ? 'Imported environment'
        : asJsonString(m['name']),
    variables: [
      for (final v in asJsonList(m['values']))
        if (asJsonString(asJsonMap(v)['key']).isNotEmpty)
          Variable(
            key: asJsonString(asJsonMap(v)['key']),
            value: jsonText(asJsonMap(v)['value']),
            secret: asJsonMap(v)['type'] == 'secret',
            enabled: asJsonMap(v)['enabled'] != false,
          ),
    ],
  );
}

/// Exports variables as a Postman environment. Secret values are exported
/// only when [includeSecrets] is true.
Json exportPostmanEnvironment(
  String name,
  List<Variable> variables, {
  bool includeSecrets = false,
}) => {
  'name': name,
  'values': [
    for (final v in variables)
      {
        'key': v.key,
        'value': v.secret && !includeSecrets ? '' : v.value,
        'type': v.secret ? 'secret' : 'default',
        'enabled': v.enabled,
      },
  ],
  '_postman_variable_scope': 'environment',
};
