import 'dart:convert';

/// The JSON a GraphQL server expects in a POST body:
/// `{"query": …, "variables": {…}, "operationName": …}`.
///
/// [variables] must be empty or a JSON object. A [FormatException] explains
/// what is wrong, so a typo is reported before anything is sent.
String graphqlPayload({
  required String query,
  String variables = '',
  String operationName = '',
}) {
  Object? vars;
  if (variables.trim().isNotEmpty) {
    try {
      vars = jsonDecode(variables);
    } on FormatException catch (e) {
      throw FormatException(
        'GraphQL variables are not valid JSON: ${e.message}',
      );
    }
    if (vars != null && vars is! Map) {
      throw const FormatException('GraphQL variables must be a JSON object');
    }
  }
  return jsonEncode({
    'query': query,
    'variables': ?vars,
    if (operationName.trim().isNotEmpty) 'operationName': operationName.trim(),
  });
}

/// Names of the operations in [query], in order. Used to pick
/// `operationName` when a document holds several. A cheap scan, not a parser:
/// it skips strings and comments and reads the name after
/// `query`/`mutation`/`subscription` at brace depth 0.
List<String> graphqlOperationNames(String query) {
  final names = <String>[];
  var depth = 0;
  var i = 0;
  while (i < query.length) {
    final c = query[i];
    if (c == '#') {
      while (i < query.length && query[i] != '\n') {
        i++;
      }
    } else if (c == '"') {
      if (query.startsWith('"""', i)) {
        final end = query.indexOf('"""', i + 3);
        i = end == -1 ? query.length : end + 3;
      } else {
        i++;
        while (i < query.length && query[i] != '"' && query[i] != '\n') {
          i += query[i] == r'\' ? 2 : 1;
        }
        i++;
      }
    } else if (c == '{' || c == '(') {
      depth++;
      i++;
    } else if (c == '}' || c == ')') {
      depth--;
      i++;
    } else if (depth == 0 && _isNameStart(c)) {
      var j = i;
      while (j < query.length && _isNamePart(query[j])) {
        j++;
      }
      final word = query.substring(i, j);
      if (word == 'query' || word == 'mutation' || word == 'subscription') {
        var k = j;
        while (k < query.length && ' \t\r\n,'.contains(query[k])) {
          k++;
        }
        var e = k;
        while (e < query.length && _isNamePart(query[e])) {
          e++;
        }
        if (e > k) names.add(query.substring(k, e));
      }
      i = j;
    } else {
      i++;
    }
  }
  return names;
}

bool _isNameStart(String c) => RegExp(r'[A-Za-z_]').hasMatch(c);
bool _isNamePart(String c) => RegExp(r'[A-Za-z0-9_]').hasMatch(c);
