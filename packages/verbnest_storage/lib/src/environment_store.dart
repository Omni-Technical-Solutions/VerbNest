import 'package:sqlite3/sqlite3.dart';
import 'package:verbnest_core/verbnest_core.dart';

import 'errors.dart';
import 'repository_models.dart';
import 'row_mapper.dart';
import 'store_support.dart';
import 'workspace_database.dart';

/// Variables (of a workspace, collection, folder or environment) and the
/// environments that group them.
class EnvironmentStore {
  EnvironmentStore(this._ws, this._clock);

  final WorkspaceDatabase _ws;
  final DateTime Function() _clock;

  Database get _db => _ws.db;

  List<Variable> variables(VariableOwner owner) => [
    for (final r in _db.select(
      'SELECT * FROM variable WHERE owner_kind = ? AND owner_id = ? ORDER BY position',
      [owner.kind, owner.id],
    ))
      Variable(
        key: r.str('key'),
        value: (r.strOrNull('value')) ?? '',
        secret: r['type'] == 'secret',
        enabled: r.flag('enabled'),
        description: r.str('description'),
      ),
  ];

  /// Replaces all variables of [owner]. Secret values are never stored
  /// (constitution II.4); they belong in the secret store.
  void saveVariables(VariableOwner owner, List<Variable> vars) =>
      _ws.transaction(() => replaceVariables(owner, vars));

  void replaceVariables(VariableOwner owner, List<Variable> vars) {
    _db.execute('DELETE FROM variable WHERE owner_kind = ? AND owner_id = ?', [
      owner.kind,
      owner.id,
    ]);
    final seen = <String>{};
    for (var i = 0; i < vars.length; i++) {
      final v = vars[i];
      if (!seen.add(v.key)) throw DuplicateNameError(v.key);
      _db.execute(
        'INSERT INTO variable(id, owner_kind, owner_id, key, value, type, enabled, description, position) '
        'VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)',
        [
          Ulid.generate(now: _clock()),
          owner.kind,
          owner.id,
          v.key,
          v.secret ? null : v.value,
          v.secret ? 'secret' : 'default',
          v.enabled ? 1 : 0,
          v.description,
          (i + 1) * positionStep,
        ],
      );
    }
  }

  List<Environment> environments() => [
    for (final r in _db.select(
      'SELECT * FROM environment ORDER BY position, name',
    ))
      Environment(
        id: r.str('id'),
        name: r.str('name'),
        color: r.strOrNull('color'),
        variables: variables(VariableOwner.environment(r.str('id'))),
      ),
  ];

  Environment environment(String id) {
    final rows = _db.select('SELECT * FROM environment WHERE id = ?', [id]);
    if (rows.isEmpty) throw NotFoundError('Environment $id');
    return environments().firstWhere((e) => e.id == id);
  }

  /// Inserts or updates [env] together with its variables.
  void saveEnvironment(Environment env) => _ws.transaction(() {
    final exists = _db.select('SELECT 1 FROM environment WHERE id = ?', [
      env.id,
    ]);
    try {
      if (exists.isEmpty) {
        _db.execute(
          'INSERT INTO environment(id, name, color, position) VALUES (?, ?, ?, ?)',
          [env.id, env.name, env.color, _nextPosition()],
        );
      } else {
        _db.execute('UPDATE environment SET name = ?, color = ? WHERE id = ?', [
          env.name,
          env.color,
          env.id,
        ]);
      }
    } on SqliteException catch (e) {
      if (e.extendedResultCode == 2067) throw DuplicateNameError(env.name);
      rethrow;
    }
    replaceVariables(VariableOwner.environment(env.id), env.variables);
  });

  int _nextPosition() {
    final max =
        _db.select('SELECT MAX(position) AS p FROM environment').first['p']
            as int?;
    return max == null ? positionStep : max + positionStep;
  }

  /// Deletes the environment and its variables. Clearing it as the workspace's
  /// default is the caller's job (that setting lives in the meta table).
  void delete(String id) => _ws.transaction(() {
    _db.execute('DELETE FROM environment WHERE id = ?', [id]);
    _db.execute(
      "DELETE FROM variable WHERE owner_kind = 'environment' AND owner_id = ?",
      [id],
    );
  });
}
