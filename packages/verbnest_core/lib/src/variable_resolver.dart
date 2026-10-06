import 'dynamic_variables.dart';
import 'variable.dart';

/// Thrown when variables reference each other in a loop. [chain] names the
/// loop, e.g. `a → b → a`.
class VariableCycleException implements Exception {
  VariableCycleException(this.chain);

  final List<String> chain;

  @override
  String toString() => 'Variable cycle: ${chain.join(' → ')}';
}

class ResolveResult {
  const ResolveResult({
    required this.value,
    this.unresolved = const {},
    this.secretNames = const {},
  });

  /// Substituted text. Contains real secret values when produced by
  /// [VariableResolver.resolve]; never log or persist it.
  final String value;

  /// `{{names}}` that no scope defines (FR-VAR-006). Left verbatim in [value].
  final Set<String> unresolved;

  /// Names of secret variables that were substituted.
  final Set<String> secretNames;

  bool get hasUnresolved => unresolved.isNotEmpty;
}

/// Substitutes `{{name}}` references (data-model §5).
class VariableResolver {
  VariableResolver(this.scopes, {DynamicVariables? dynamic})
    : _dynamic = dynamic ?? DynamicVariables();

  static const maxDepth = 10;
  static const maskText = '••••••';
  static final _reference = RegExp(r'\{\{([^{}]*)\}\}');

  final VariableScopes scopes;
  final DynamicVariables _dynamic;

  /// Resolves [input] with real secret values, for sending.
  ResolveResult resolve(String input) => _run(input, mask: false);

  /// Resolves [input] with secret values replaced by [maskText], safe for
  /// history, logs and exports (constitution VII).
  ResolveResult resolveMasked(String input) => _run(input, mask: true);

  ResolveResult _run(String input, {required bool mask}) {
    final state = _State(mask);
    final value = _expand(input, const [], state);
    return ResolveResult(
      value: value,
      unresolved: state.unresolved,
      secretNames: state.secrets,
    );
  }

  String _expand(String input, List<String> chain, _State state) {
    return input.replaceAllMapped(_reference, (m) {
      final name = m.group(1)!.trim();
      return _substitute(m.group(0)!, name, chain, state);
    });
  }

  String _substitute(
    String original,
    String name,
    List<String> chain,
    _State state,
  ) {
    if (name.startsWith(r'$')) {
      final generated = _dynamic.generate(name);
      if (generated != null) return generated;
    }
    final found = name.startsWith(r'$') ? null : scopes.lookup(name);
    if (found == null) {
      state.unresolved.add(name);
      return original;
    }
    if (found.variable.secret) {
      state.secrets.add(name);
      if (state.mask) return maskText;
    }
    return _expand(found.variable.value, _descend(chain, name), state);
  }

  List<String> _descend(List<String> chain, String name) {
    final index = chain.indexOf(name);
    if (index != -1) {
      throw VariableCycleException([...chain.sublist(index), name]);
    }
    if (chain.length >= maxDepth) {
      throw VariableCycleException([...chain, name]);
    }
    return [...chain, name];
  }
}

class _State {
  _State(this.mask);

  final bool mask;
  final Set<String> unresolved = {};
  final Set<String> secrets = {};
}
