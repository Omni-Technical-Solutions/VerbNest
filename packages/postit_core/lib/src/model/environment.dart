import '../variable.dart';

/// A named set of variables (FR-VAR-004). Initial values live in the
/// workspace; secret values live in the secret store, so a secret
/// [Variable] here has an empty value.
class Environment {
  const Environment({
    required this.id,
    required this.name,
    this.color,
    this.variables = const [],
  });

  final String id;
  final String name;
  final String? color;
  final List<Variable> variables;

  Environment copyWith({
    String? name,
    String? color,
    List<Variable>? variables,
  }) => Environment(
    id: id,
    name: name ?? this.name,
    color: color ?? this.color,
    variables: variables ?? this.variables,
  );
}
