/// `PRAGMA application_id` of every workspace database ("POST").
const workspaceApplicationId = 0x504F5354;

/// Forward-only migrations. Entry `i` upgrades schema `i` to `i + 1`, and
/// `PRAGMA user_version` holds the current schema. Never edit a released
/// entry; append a new one.
const workspaceMigrations = <String>[
  // v1 (data-model.md §1.1)
  '''
CREATE TABLE meta (key TEXT PRIMARY KEY, value TEXT NOT NULL);

CREATE TABLE node (
  id           TEXT PRIMARY KEY,
  parent_id    TEXT REFERENCES node(id) ON DELETE CASCADE,
  kind         TEXT NOT NULL CHECK (kind IN ('collection','folder','request')),
  type         TEXT,
  name         TEXT NOT NULL,
  position     INTEGER NOT NULL,
  description  TEXT NOT NULL DEFAULT '',
  auth_json    TEXT,
  scripts_json TEXT,
  data         TEXT NOT NULL DEFAULT '{}',
  extra        TEXT NOT NULL DEFAULT '{}',
  created_at   INTEGER NOT NULL,
  updated_at   INTEGER NOT NULL
);
CREATE INDEX node_parent ON node(parent_id, position);

CREATE TABLE example (
  id         TEXT PRIMARY KEY,
  request_id TEXT NOT NULL REFERENCES node(id) ON DELETE CASCADE,
  name       TEXT NOT NULL,
  position   INTEGER NOT NULL,
  data       TEXT NOT NULL,
  body_blob  BLOB
);

CREATE TABLE environment (
  id       TEXT PRIMARY KEY,
  name     TEXT NOT NULL UNIQUE,
  color    TEXT,
  position INTEGER NOT NULL
);

CREATE TABLE variable (
  id          TEXT PRIMARY KEY,
  owner_kind  TEXT NOT NULL CHECK (owner_kind IN ('global','environment','collection','folder')),
  owner_id    TEXT NOT NULL DEFAULT '',
  key         TEXT NOT NULL,
  value       TEXT,
  type        TEXT NOT NULL DEFAULT 'default' CHECK (type IN ('default','secret')),
  enabled     INTEGER NOT NULL DEFAULT 1,
  description TEXT NOT NULL DEFAULT '',
  position    INTEGER NOT NULL,
  UNIQUE (owner_kind, owner_id, key)
);

CREATE TABLE revision (
  node_id  TEXT NOT NULL REFERENCES node(id) ON DELETE CASCADE,
  rev      INTEGER NOT NULL,
  saved_at INTEGER NOT NULL,
  snapshot TEXT NOT NULL,
  PRIMARY KEY (node_id, rev)
);

CREATE TABLE attachment (
  id         TEXT PRIMARY KEY,
  name       TEXT NOT NULL,
  mime       TEXT,
  content    BLOB NOT NULL,
  created_at INTEGER NOT NULL
);
''',
];

int get workspaceSchemaVersion => workspaceMigrations.length;
