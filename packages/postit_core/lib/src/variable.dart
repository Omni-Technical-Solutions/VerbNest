/// A single variable as stored in a scope (FR-VAR-002).
class Variable {
  const Variable({
    required this.key,
    this.value = '',
    this.secret = false,
    this.enabled = true,
    this.description = '',
  });

  final String key;
  final String value;
  final bool secret;
  final bool enabled;
  final String description;
}

/// Scopes in precedence order, highest first (FR-VAR-001).
enum VariableScope { local, data, environment, collection, global }

/// The scope stack used to resolve `{{name}}` references.
class VariableScopes {
  VariableScopes({
    Iterable<Variable> local = const [],
    Iterable<Variable> data = const [],
    Iterable<Variable> environment = const [],
    Iterable<Variable> collection = const [],
    Iterable<Variable> global = const [],
  }) : _scopes = {
         VariableScope.local: _index(local),
         VariableScope.data: _index(data),
         VariableScope.environment: _index(environment),
         VariableScope.collection: _index(collection),
         VariableScope.global: _index(global),
       };

  final Map<VariableScope, Map<String, Variable>> _scopes;

  static Map<String, Variable> _index(Iterable<Variable> vars) => {
    for (final v in vars)
      if (v.enabled) v.key: v,
  };

  /// Returns the highest-precedence enabled variable named [key], or null.
  ResolvedVariable? lookup(String key) {
    for (final scope in VariableScope.values) {
      final v = _scopes[scope]![key];
      if (v != null) return ResolvedVariable(v, scope);
    }
    return null;
  }

  /// Every visible variable with its source scope (for the quick-look panel,
  /// FR-VAR-004). Shadowed variables are omitted.
  List<ResolvedVariable> visible() {
    final seen = <String>{};
    final out = <ResolvedVariable>[];
    for (final scope in VariableScope.values) {
      for (final v in _scopes[scope]!.values) {
        if (seen.add(v.key)) out.add(ResolvedVariable(v, scope));
      }
    }
    return out;
  }
}

class ResolvedVariable {
  const ResolvedVariable(this.variable, this.scope);

  final Variable variable;
  final VariableScope scope;
}
