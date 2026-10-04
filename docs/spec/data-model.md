# Data Model

Three stores, with different jobs (ADR-007):

| Store | Holds | Shared? |
|---|---|---|
| **Workspace database** (`<name>.postit`, SQLite via drift) | Collections, folders, requests, examples, environments, variables (initial values), scripts, workspace settings, per-request revisions, attached files (protos, data files) | Yes: copy/export the file |
| **Local database** (SQLite via drift, per device, in app support dir) | History, run results, search index (FTS5), current variable values, cookies, OAuth token metadata, UI tabs/layout, recent workspaces | No |
| **Secret store** (OS keychain) | Secret variable values, OAuth tokens, cert passphrases | No |

## 1. Workspace database

One SQLite file per workspace. Opened in WAL mode with `foreign_keys=ON`; the app holds an exclusive lock while a workspace is open. Default location: `<app documents>/workspaces/<workspace id>.postit`. On desktop a workspace may also be opened in place from any path.

Rules:
- Every entity has a stable `id` (ULID) so history, run results and tabs refer to it across renames and moves.
- Sibling order is the integer `position` column (gaps allowed, renumbered on demand). Moving a node changes `parent_id` and `position` only.
- Request bodies and type-specific fields live in a JSON document column (`data`) validated against the v1 schemas in §2; columns that are queried (name, kind, type, url, parent, position) are real columns.
- Unknown keys inside `data`, `auth`, `scripts` and `extra` JSON are preserved on read/write (forward compatibility).
- All edits are transactions. Each saved edit of a request appends a `revision` row (last 50 kept per node by default) to provide version history without git.
- `PRAGMA user_version` holds the schema version; migrations are forward-only and covered by drift schema-dump tests.

### 1.1 Schema (v1)

```sql
CREATE TABLE meta (key TEXT PRIMARY KEY, value TEXT NOT NULL);
-- keys: workspace_id, name, default_environment_id, settings_json, created_at

CREATE TABLE node (
  id          TEXT PRIMARY KEY,                 -- ULID
  parent_id   TEXT REFERENCES node(id) ON DELETE CASCADE,  -- NULL = top level (collections)
  kind        TEXT NOT NULL CHECK (kind IN ('collection','folder','request')),
  type        TEXT,                             -- request type: http|graphql|websocket|sse|grpc|...; NULL for collection/folder
  name        TEXT NOT NULL,
  position    INTEGER NOT NULL,
  description TEXT NOT NULL DEFAULT '',
  auth_json   TEXT,                             -- see §2.2/§2.5
  scripts_json TEXT,                            -- {pre, post}
  data        TEXT NOT NULL DEFAULT '{}',       -- type-specific request fields (§2.2, §2.6)
  extra       TEXT NOT NULL DEFAULT '{}',       -- unknown/forward-compat and x-postman keys
  created_at  INTEGER NOT NULL,
  updated_at  INTEGER NOT NULL
);
CREATE INDEX node_parent ON node(parent_id, position);

CREATE TABLE example (
  id TEXT PRIMARY KEY,
  request_id TEXT NOT NULL REFERENCES node(id) ON DELETE CASCADE,
  name TEXT NOT NULL, position INTEGER NOT NULL,
  data TEXT NOT NULL,                           -- request snapshot + response (§2.3)
  body_blob BLOB                                -- binary response body, if any
);

CREATE TABLE environment (
  id TEXT PRIMARY KEY, name TEXT NOT NULL UNIQUE, color TEXT, position INTEGER NOT NULL
);

CREATE TABLE variable (                          -- initial values only; secrets store no value
  id TEXT PRIMARY KEY,
  owner_kind TEXT NOT NULL CHECK (owner_kind IN ('global','environment','collection','folder')),
  owner_id TEXT,                                -- environment.id or node.id; NULL for global
  key TEXT NOT NULL, value TEXT,
  type TEXT NOT NULL DEFAULT 'default' CHECK (type IN ('default','secret')),
  enabled INTEGER NOT NULL DEFAULT 1, description TEXT NOT NULL DEFAULT '',
  position INTEGER NOT NULL,
  UNIQUE (owner_kind, owner_id, key)
);

CREATE TABLE revision (
  node_id TEXT NOT NULL REFERENCES node(id) ON DELETE CASCADE,
  rev INTEGER NOT NULL, saved_at INTEGER NOT NULL,
  snapshot TEXT NOT NULL,                       -- full JSON of the node at save time
  PRIMARY KEY (node_id, rev)
);

CREATE TABLE attachment (                        -- protos, descriptor sets, runner data files, binary bodies
  id TEXT PRIMARY KEY, name TEXT NOT NULL, mime TEXT, content BLOB NOT NULL, created_at INTEGER NOT NULL
);
```

References to files inside a request (binary body, multipart file part, proto file, data file) point to an `attachment.id`, or to a device path that is stored only in the local database (so a shared workspace never contains absolute paths from another machine).

### 1.2 Export, import and sharing (replaces file layout)

| Operation | Result | Priority |
|---|---|---|
| Copy `.postit` file / "Export workspace" | Consistent copy made with `VACUUM INTO`, no history, no current values, no secrets | P0 |
| Export Postman v2.1, cURL | See §6 | P0 |
| **Export YAML snapshot** to a folder | Writes the tree below from the database; deterministic output so it diffs cleanly in git | P1 |
| **Import YAML snapshot** | Reads that tree into a new workspace or merges into the open one (by `id`, with a conflict list) | P1 |

YAML snapshot layout (same shapes as §2):

```
my-api/
  postit.yaml                        workspace manifest
  globals.yaml
  environments/dev.yaml ...
  collections/petstore/_collection.yaml
  collections/petstore/pets/_folder.yaml
  collections/petstore/pets/list-pets.req.yaml
  collections/petstore/pets/create-pet.examples/201-created.example.yaml
  protos/ data/                      attachments written as files
```
Sibling order is written as `order: [...]` in each `_folder.yaml`/`_collection.yaml`. Export → import → export MUST be byte-identical (testing.md).

## 2. Document schemas (v1)

These are the shapes of the JSON stored in `node.data`, `auth_json`, `scripts_json` and `example.data`, and of the YAML snapshot files. YAML is shown because it is easier to read; the database stores the same structure as JSON.

### 2.1 `postit.yaml`
```yaml
postit: 1                    # format version
id: 01J9Z3...                # ULID
name: My API
defaultEnvironment: dev
settings:
  http: { timeoutMs: 30000, followRedirects: true, maxRedirects: 10, verifyTls: true }
  history: { maxEntries: 5000, maxAgeDays: 30, storeBodies: true }
```

### 2.2 HTTP request `*.req.yaml`
```yaml
id: 01J9Z4...
name: Create pet
type: http
method: POST
url: "{{baseUrl}}/pets/:petId?verbose=true"
params:                      # query; kept in sync with url
  - { key: verbose, value: "true", enabled: true }
pathVars:
  - { key: petId, value: "{{petId}}" }
headers:
  - { key: Content-Type, value: application/json }
  - { key: X-Trace, value: "{{$guid}}", enabled: false, description: debug only }
body:
  mode: json                 # none|json|xml|text|html|javascript|form|urlencoded|binary|graphql
  json: |
    { "name": "Rex", "tag": "{{tag}}" }
  # form: [{ key, value, type: text|file, src, contentType, enabled }]
  # urlencoded: [{ key, value, enabled }]
  # binary: { src: ./fixtures/img.png }
auth:
  type: inherit              # inherit|none|apikey|bearer|basic|digest|oauth2|jwt|awsv4|oauth1|hawk|ntlm|edgegrid|asap
settings:
  timeoutMs: 10000
  verifyTls: true
  httpVersion: auto          # auto|http1|http2
scripts:
  pre: |
    pm.variables.set("tag", "dog");
  post: |
    pm.test("201", () => pm.response.to.have.status(201));
assertions:                  # no-code assertions (P1), compiled to script at run time
  - { target: status, op: eq, value: 201 }
  - { target: jsonPath, path: "$.id", op: exists }
description: |
  Creates a pet. **Markdown** supported.
```

### 2.3 Example `*.example.yaml`
```yaml
id: 01J9Z5...
name: 201 created
request: { method: POST, url: "{{baseUrl}}/pets", headers: [...], body: {...} }   # snapshot, optional
response:
  status: 201
  headers: [{ key: Content-Type, value: application/json }]
  body: '{ "id": 1, "name": "Rex" }'
  bodyFile: ./201-created.body.bin   # alternative for binary
```

### 2.4 Environment `environments/<name>.yaml`
```yaml
id: 01J9Z6...
name: dev
color: "#2E7D32"             # used for env badge; red-ish for prod warns on send (setting)
variables:
  - { key: baseUrl, value: "https://dev.api.example.com", enabled: true }
  - { key: apiKey, type: secret, enabled: true }   # value lives in SecretStore, never here
  - { key: tag, value: cat, description: default tag }
```
Per-device overrides are the *current values* kept in the local database (§4); they win over the workspace's initial values on this device and are never exported.

### 2.5 Collection / folder meta (`_collection.yaml`, `_folder.yaml`)
```yaml
id: 01J9Z7...
name: Petstore
order: [pets, auth, chat]
auth: { type: bearer, token: "{{accessToken}}" }
variables: [{ key: petId, value: "1" }]
scripts: { pre: "...", post: "..." }
description: "..."
```

### 2.6 Other request types (abridged)
```yaml
# chat.ws.yaml
type: websocket
url: wss://{{host}}/chat
headers: [...]
subprotocols: [chat.v1]
messages:                    # saved messages
  - { name: hello, format: json, body: '{"type":"hello"}' }
settings: { autoReconnect: false, pingIntervalMs: 0 }

# catalog.gql.yaml
type: graphql
url: "{{baseUrl}}/graphql"
query: |
  query Pets($first: Int) { pets(first: $first) { id name } }
variables: '{ "first": 10 }'
operationName: Pets
schemaSource: introspection  # introspection|file
schemaFile: null

# inventory.grpc.yaml
type: grpc
target: "{{grpcHost}}:443"
tls: true
service: inventory.v1.Inventory
method: ListItems
descriptorSource: reflection # reflection|descriptorSet|proto
protoFiles: [attachment:01J9ZA...]   # attachment id (YAML snapshot: ../../protos/inventory.proto)
metadata: [{ key: authorization, value: "Bearer {{token}}" }]
message: |
  { "pageSize": 20 }
deadlineMs: 5000
```

Auth block shapes mirror Postman's auth types (e.g. `oauth2: { grantType, accessTokenUrl, authUrl, clientId, clientSecret, scope, usePkce, tokenName, addTokenTo: header|query, headerPrefix }`), with secret fields allowed to be `{{var}}` references so the actual secret lives in a secret variable.

## 3. Domain model (Dart, `postit_core`)

```
Workspace(id, name, dbPath, settings, collections[], environments[], globals)
Collection(id, name, auth, variables[], scripts, description, children: Node[])
Folder(id, name, auth, variables[], scripts, description, children: Node[])
sealed Node = Folder | RequestItem
sealed RequestItem(id, name, description, scripts, assertions[]) =
    HttpRequest(method, url, params[], pathVars[], headers[], body, auth, settings, examples[])
  | GraphQLRequest(url, query, variables, operationName, headers[], auth, schemaSource)
  | WebSocketRequest(url, headers[], subprotocols[], messages[], settings)
  | SseRequest(url, headers[], auth, settings)
  | SocketIoRequest(url, version, events[], ...)
  | GrpcRequest(target, tls, service, method, descriptorSource, metadata[], message, deadline)
  | JsonRpcRequest | SoapRequest | MqttRequest | McpRequest   (P2)
KeyValue(key, value, enabled, description, type: text|file|secret)
Variable(key, initialValue?, type: default|secret, enabled, description)
Environment(id, name, color, variables[])
Auth (sealed per type)
Example(id, name, requestSnapshot?, ResponseSnapshot)
```

Runtime (not persisted in the workspace database):
```
ResolvedRequest(method, url, headers[], bodyBytes|bodyStream, settings, certs, proxy)
ResponseRecord(status, reason, httpVersion, headers[], bodyRef, sizes, timings, tlsInfo, remoteAddress)
Timings(dnsMs, connectMs, tlsMs, requestSentMs, ttfbMs, downloadMs, totalMs)
ExecutionContext(scopes: VariableScopes, cookieJar, console, testResults[])
VariableScopes(local, data, environment, collection, global)
```

## 4. Local database schema (drift, per device)

Holds device-local state only. Everything here is either discardable or rebuildable; deleting this database MUST NOT lose workspace content (constitution II). `search_idx` is derived from the workspace database and rebuilt when out of date.

```sql
CREATE TABLE workspace (id TEXT PRIMARY KEY, name TEXT, db_path TEXT, bookmark BLOB, last_opened_at INTEGER);  -- recent workspaces; bookmark = security-scoped/SAF handle for externally opened files

CREATE TABLE local_path (workspace_id TEXT, ref TEXT, path TEXT, PRIMARY KEY (workspace_id, ref));  -- device file paths for request file references, never shared

CREATE TABLE history (
  id TEXT PRIMARY KEY, workspace_id TEXT, request_id TEXT NULL,   -- null for ad-hoc
  type TEXT, method TEXT, url TEXT, environment_name TEXT,
  sent_at INTEGER, status INTEGER, total_ms INTEGER,
  request_json TEXT,            -- resolved request, secrets masked
  response_meta_json TEXT,      -- headers, timings, tls
  response_body BLOB NULL,      -- capped (default 1 MB) or NULL
  body_truncated INTEGER, error TEXT NULL
);
CREATE INDEX history_ws_time ON history(workspace_id, sent_at DESC);

CREATE TABLE variable_current (       -- current values, never written to the workspace database
  workspace_id TEXT, scope TEXT, scope_id TEXT, key TEXT, value TEXT,
  PRIMARY KEY (workspace_id, scope, scope_id, key));

CREATE TABLE run (id TEXT PRIMARY KEY, workspace_id TEXT, target_id TEXT, started_at INTEGER,
  finished_at INTEGER, iterations INTEGER, passed INTEGER, failed INTEGER, environment_name TEXT, options_json TEXT);
CREATE TABLE run_step (run_id TEXT, iteration INTEGER, seq INTEGER, request_id TEXT, name TEXT,
  status INTEGER, total_ms INTEGER, tests_json TEXT, error TEXT, PRIMARY KEY (run_id, iteration, seq));

CREATE TABLE cookie (workspace_id TEXT, domain TEXT, path TEXT, name TEXT, value TEXT,
  expires INTEGER NULL, secure INTEGER, http_only INTEGER, same_site TEXT,
  PRIMARY KEY (workspace_id, domain, path, name));

CREATE TABLE oauth_token (id TEXT PRIMARY KEY, workspace_id TEXT, config_hash TEXT, name TEXT,
  expires_at INTEGER, scopes TEXT, secret_ref TEXT);  -- token value in SecretStore

CREATE TABLE ui_tab (workspace_id TEXT, seq INTEGER, request_id TEXT NULL, draft_json TEXT NULL,
  pinned INTEGER, PRIMARY KEY (workspace_id, seq));

CREATE VIRTUAL TABLE search_idx USING fts5(workspace_id UNINDEXED, entity_id UNINDEXED, kind, name, url, body, description);
```

Drift migrations are versioned and tested (`drift_dev` schema dumps) for every release.

## 5. Variable resolution

1. Build scope stack for the request: `local` (set by scripts this execution) → `data` (runner iteration row) → active `environment` (current value ?? local override ?? initial value) → `collection` (with folder variables layered nearest-first, P1) → `global`.
2. Replace `{{name}}` occurrences in URL, params, path vars, headers, body (text modes), auth fields, GraphQL variables, gRPC message and metadata. Names may contain any char except `{}`; whitespace is trimmed.
3. Values are resolved recursively up to depth 10; cycles produce an error that names the chain (`a → b → a`).
4. `{{$dynamic}}` names are evaluated once per occurrence per send (Postman behaviour).
5. Disabled variables are invisible. Secret values are injected at send time and masked in every record afterwards.
6. Unresolved names are left verbatim and reported (FR-VAR-006).

## 6. Postman mapping

| Postman v2.1 | PostIt |
|---|---|
| `info` | `node` row, kind `collection`: name/description (Postman `_postman_id` kept as `postmanId` in `extra`) |
| `item[]` with `item[]` | `node` row, kind `folder`, with `parent_id` and `position` |
| `item[]` with `request` | `node` row, kind `request`, type `http` |
| `request.url` (object or string) | `data.url` string + `params` + `pathVars` |
| `request.body.mode` raw + `options.raw.language` | `data.body.mode` json/xml/text/html/javascript |
| `response[]` | `example` rows |
| `event[]` listen `prerequest`/`test` | `scripts_json.pre` / `scripts_json.post` |
| `variable[]` | `variable` rows (owner kind `collection` or `folder`) |
| `auth` | `auth_json` (types 1:1) |
| `protocolProfileBehavior` | `data.settings` (known keys mapped, rest kept under `settings.postman`) |

Unknown Postman fields are kept under an `x-postman` key in `node.extra` so export round-trips.
