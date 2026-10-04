# Data Model

Two stores, with different jobs:

| Store | Holds | Shared via git? |
|---|---|---|
| **Workspace files** (YAML) | Collections, folders, requests, examples, environments (initial values), collection/global variables (initial values), scripts, workspace settings | Yes |
| **App database** (SQLite via drift, per device) | History, run results, search index, current variable values, UI state, token metadata | No |
| **Secret store** (OS keychain) | Secret variable values, OAuth tokens, cert passphrases | No |

## 1. Workspace layout on disk

```
my-api/                              ← workspace root (can be a git repo)
  postit.yaml                        workspace manifest
  .gitignore                         generated: *.local.yaml, .postit/cache/
  globals.yaml                       global variables (initial values)
  environments/
    dev.yaml
    staging.yaml
    prod.yaml
    dev.local.yaml                   optional local overrides (git-ignored)
  collections/
    petstore/
      _collection.yaml               collection meta: auth, vars, scripts, description
      pets/
        _folder.yaml                 folder meta
        list-pets.req.yaml
        create-pet.req.yaml
        create-pet.examples/
          201-created.example.yaml
      auth/
        _folder.yaml
        login.req.yaml
      chat.ws.yaml                   WebSocket request
      events.sse.yaml                SSE request
      catalog.gql.yaml               GraphQL request
      inventory.grpc.yaml            gRPC request
  protos/                            optional .proto / descriptor sets
  data/                              runner data files (CSV/JSON)
  .postit/
    plugins/                         (P2)
    cache/                           introspection & reflection caches (git-ignored)
```

Rules:
- Ordering of siblings is stored in the parent's `_folder.yaml` / `_collection.yaml` as `order: [list-pets, create-pet]`; files missing from `order` sort alphabetically after listed ones (so hand-added files still appear).
- File names are slugs derived from the display name; the display name is stored inside the file so renames of the display name don't have to rename files (renaming file is optional, done by the app on rename by default).
- Every entity has a stable `id` (ULID) so history, run results and tabs can refer to it across renames and moves.
- Unknown keys are preserved on read/write (forward compatibility).

## 2. File schemas (v1)

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
Local overrides file `dev.local.yaml` has the same shape and only `variables`; its values win over the shared file's initial values on this device.

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
protoFiles: [../../protos/inventory.proto]
metadata: [{ key: authorization, value: "Bearer {{token}}" }]
message: |
  { "pageSize": 20 }
deadlineMs: 5000
```

Auth block shapes mirror Postman's auth types (e.g. `oauth2: { grantType, accessTokenUrl, authUrl, clientId, clientSecret, scope, usePkce, tokenName, addTokenTo: header|query, headerPrefix }`), with secret fields allowed to be `{{var}}` references so the actual secret lives in a secret variable.

## 3. Domain model (Dart, `postit_core`)

```
Workspace(id, name, rootPath, settings, collections[], environments[], globals)
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

Runtime (not persisted to files):
```
ResolvedRequest(method, url, headers[], bodyBytes|bodyStream, settings, certs, proxy)
ResponseRecord(status, reason, httpVersion, headers[], bodyRef, sizes, timings, tlsInfo, remoteAddress)
Timings(dnsMs, connectMs, tlsMs, requestSentMs, ttfbMs, downloadMs, totalMs)
ExecutionContext(scopes: VariableScopes, cookieJar, console, testResults[])
VariableScopes(local, data, environment, collection, global)
```

## 4. Database schema (drift, per device)

```sql
CREATE TABLE workspace (id TEXT PRIMARY KEY, name TEXT, root_path TEXT, bookmark BLOB, last_opened_at INTEGER);

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

CREATE TABLE variable_current (       -- current values, never written to workspace files
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
| `info` | `_collection.yaml` name/description/id (Postman `_postman_id` preserved as `postmanId`) |
| `item[]` with `item[]` | Folder directory + `_folder.yaml` |
| `item[]` with `request` | `*.req.yaml` |
| `request.url` (object or string) | `url` string + `params` + `pathVars` |
| `request.body.mode` raw + `options.raw.language` | `body.mode` json/xml/text/html/javascript |
| `response[]` | `*.examples/` files |
| `event[]` listen `prerequest`/`test` | `scripts.pre` / `scripts.post` |
| `variable[]` | `variables` |
| `auth` | `auth` (types 1:1) |
| `protocolProfileBehavior` | `settings` (known keys mapped, rest kept under `settings.postman`) |

Unknown Postman fields are kept under an `x-postman` key so export round-trips.
