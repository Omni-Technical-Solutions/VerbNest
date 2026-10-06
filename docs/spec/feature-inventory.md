# Feature Inventory: Postman reviewed, mapped to Verbnest

This inventory walks through Postman's feature set as of late 2026 (desktop app, web app, Newman/Postman CLI, and platform features), and decides for each one whether Verbnest builds it, when, and how it differs.

Priority key: **P0** MVP · **P1** v1 · **P2** later · **—** out of scope.
"Mobile" notes cover Android/iOS-specific behaviour; everything else applies to all five platforms.

---

## 1. Request building (HTTP/REST)

| Postman feature | Verbnest | Priority | Notes |
|---|---|---|---|
| Methods GET/POST/PUT/PATCH/DELETE/HEAD/OPTIONS | Yes | P0 | Plus custom method strings (e.g. `PROPFIND`, `PURGE`). |
| URL bar with `{{var}}` highlighting & autocomplete | Yes | P0 | Unresolved vars shown in red; hover/long-press shows value and scope. |
| Query params table synced with URL | Yes | P0 | Two-way sync, enable/disable per row, bulk-edit text mode. |
| Path variables (`/users/:id`) | Yes | P0 | Auto-detected, shown in Params tab. |
| Headers table, auto-generated headers (hidden/visible) | Yes | P0 | Auto headers (Host, Content-Length, User-Agent, Accept-Encoding) visible and individually overridable. |
| Header presets | Yes | P1 | |
| Body: none, form-data, x-www-form-urlencoded, raw (JSON/XML/HTML/Text/JS), binary | Yes | P0 | form-data supports file parts; mobile uses system file picker. |
| Body: GraphQL | Yes | P1 | See §6. |
| Per-request settings (TLS verify, redirects, timeout, encoding, HTTP version) | Yes | P0 | HTTP/2 P1 (see architecture.md for platform limits). HTTP/3 P2. |
| Request descriptions (Markdown) | Yes | P1 | Rendered Markdown; also used for docs export. |
| Tabs, multiple open requests, unsaved-changes indicator | Yes | P0 | Desktop: tab strip. Mobile: stack navigation + "open requests" switcher. |
| Request duplicate, rename, move, drag & drop | Yes | P0 | |
| Cookies manager (per domain) | Yes | P1 | Persistent cookie jar per workspace; manual edit. |
| Postman Interceptor / capture from browser | — | — | Out of scope; offer HAR import instead. |
| Built-in proxy capture | Later | P2 | Desktop only. |

## 2. Response viewing

| Postman feature | Verbnest | Priority | Notes |
|---|---|---|---|
| Status, time, size | Yes | P0 | Size split into headers/body; compressed vs. decompressed. |
| Pretty / Raw / Preview views | Yes | P0 | Pretty with syntax highlighting & folding for JSON/XML/HTML. Preview: HTML via webview (P1), images, PDF (P1). |
| Response headers & cookies tabs | Yes | P0 | |
| Timing breakdown (DNS, TCP, TLS, TTFB, download) | Yes | P1 | Full breakdown on desktop via custom socket layer; mobile best-effort (see architecture). |
| Network info (local/remote IP, TLS cert, protocol) | Yes | P1 | |
| Search in response, JSONPath/XPath filter | Yes | P0 search, P1 filter | |
| Save response as example | Yes | P1 | Examples power the mock server. |
| Save response to file | Yes | P0 | Mobile: share sheet / Files. |
| Visualizer (`pm.visualizer.set` with HTML templates) | Yes | P2 | Webview-based; sandboxed. |
| Large response handling (stream to disk, truncate preview) | Yes | P0 | Bodies > 10 MB stream to temp file; preview limited. |

## 3. Collections & organisation

| Postman feature | Verbnest | Priority | Notes |
|---|---|---|---|
| Collections with nested folders | Yes | P0 | Stored as a directory tree of files (see data-model.md). |
| Collection/folder-level auth, variables, scripts | Yes | P0 auth & vars, P1 scripts | Inherited down the tree. |
| Workspaces (personal/team/public) | Partial | P0 | A workspace = a local SQLite file (`.verbnest`). Multiple workspaces switchable. Team/public workspaces replaced by file/snapshot exchange. |
| Forking, pull requests, merge of collections | Via snapshots | P1 | Export a YAML snapshot into a git repo and use normal git branching and merging; import merges back. No proprietary fork model. |
| Version history of collections | Replaced | P1 | Built-in per-request revision history with diff and restore (FR-WS-008). |
| Comments on requests | — | — | Use git/PR tooling instead. |
| Search across workspace | Yes | P0 | Full-text over names, URLs, bodies (SQLite FTS5 index). |
| Favourites / pinned requests | Yes | P1 | Especially valuable on mobile. |
| Postman Flows (visual low-code chaining) | Later | P2 | Consider a simpler "request chain" view first. |

## 4. Variables & environments

| Postman feature | Verbnest | Priority | Notes |
|---|---|---|---|
| Scopes: global, collection, environment, data, local | Yes | P0 (data in P1) | Same precedence as Postman: local > data > environment > collection > global. |
| Initial vs. current value | Yes | P0 | Initial value goes in files (shared); current value stays local (not committed). |
| Secret variable type (masked) | Yes | P0 | Stored in OS secure store. |
| Dynamic variables (`{{$guid}}`, `{{$timestamp}}`, `{{$randomInt}}`, faker set) | Yes | P0 core set, P1 full faker set | |
| Environment quick-switcher & quick-look | Yes | P0 | |
| Postman Vault (external secret managers: Vault, AWS SM, Azure KV) | Later | P2 | Provider interface; start with 1Password CLI/HashiCorp Vault on desktop. |

## 5. Authorization

| Postman auth type | Verbnest | Priority |
|---|---|---|
| No auth, Inherit from parent | Yes | P0 |
| API Key (header / query) | Yes | P0 |
| Bearer token | Yes | P0 |
| Basic auth | Yes | P0 |
| Digest auth | Yes | P1 |
| OAuth 2.0 (auth code, auth code + PKCE, implicit, password, client credentials, refresh, token manager) | Yes | P1 (client credentials + password in P0) |
| OAuth 1.0 | Yes | P2 |
| JWT bearer (sign with secret/key) | Yes | P1 |
| AWS Signature v4 | Yes | P1 |
| Hawk, Akamai EdgeGrid, NTLM | Yes | P2 (NTLM desktop only) |
| ASAP (Atlassian) | Yes | P2 |
| Client certificates (mTLS, PEM/PFX per host) | Yes | P1 |

OAuth 2.0 browser flows: desktop uses a loopback redirect server; mobile uses `flutter_web_auth_2` with a custom scheme / universal link (see architecture.md).

## 6. Protocols beyond REST

| Postman feature | Verbnest | Priority | Notes |
|---|---|---|---|
| GraphQL (query editor, variables, schema introspection, autocomplete, schema explorer) | Yes | P1 | Introspection cached per endpoint. |
| WebSocket (raw) | Yes | P1 | Message log, saved messages, send JSON/text/binary, auto-reconnect option. |
| Socket.IO | Yes | P2 | Via `socket_io_client`. |
| Server-Sent Events | Yes | P1 | Event stream log with filtering. Postman treats SSE as an HTTP response mode; Verbnest adds a dedicated viewer. |
| gRPC (unary, server/client/bidi streaming, reflection, .proto import, metadata, TLS) | Yes | P2 | Requires dynamic protobuf (no codegen at runtime); see architecture.md. |
| MQTT (connect, subscribe, publish, QoS) | Yes | P2 | |
| SOAP / XML-RPC / JSON-RPC | Yes | P2 | Request templates over HTTP; WSDL import P2. |
| AI / LLM request type (Postman AI requests, MCP client) | Later | P2 | MCP server testing is a natural fit for "remote function calls"; spike in Phase 4. |

## 7. Scripting & tests

| Postman feature | Verbnest | Priority | Notes |
|---|---|---|---|
| Pre-request scripts (JavaScript) | Yes | P1 | Collection → folder → request order, same as Postman. |
| Post-response / test scripts | Yes | P1 | |
| `pm.*` API: `pm.environment`, `pm.variables`, `pm.collectionVariables`, `pm.globals`, `pm.request`, `pm.response`, `pm.test`, `pm.expect` (Chai), `pm.sendRequest`, `pm.cookies`, `pm.info`, `pm.execution.setNextRequest`/`skipRequest` | Yes | P1 | Compatibility target: run the Postman script examples corpus unmodified. |
| Built-in libraries (lodash, moment, crypto-js, cheerio, xml2js, tv4/ajv, uuid, chai) | Yes | P1 (lodash, crypto-js, chai, uuid, ajv), P2 rest | Bundled into the JS runtime snapshot. |
| `require` of external npm packages / Package Library | Later | P2 | Workspace-local "script library" files first. |
| Snippets panel | Yes | P1 | |
| Test results tab with pass/fail | Yes | P1 | |
| Console (logs, network, errors) | Yes | P0 network log, P1 script logs | |
| No-code assertions (status == 200, JSONPath equals…) | Yes | P1 | Generates script under the hood; friendlier on mobile. |
| Postbot / AI test generation | Later | P2 | Optional, bring-your-own-key LLM provider. |

## 8. Running & automation

| Postman feature | Verbnest | Priority | Notes |
|---|---|---|---|
| Collection Runner (order, iterations, delay, data file CSV/JSON) | Yes | P1 | Run results saved; export JUnit/JSON/HTML. |
| Performance / load testing (virtual users, ramp-up) | Later | P2 | Desktop only; modest limits. |
| Newman / Postman CLI | Yes | P2 | `verbnest` CLI from the pure Dart core, compiled with `dart compile exe`. |
| Monitors (scheduled cloud runs) | Partial | P2 | Replaced by CLI + CI templates (GitHub Actions). Optional local scheduled runs on desktop. |
| Webhooks triggering collections | — | — | Use CI. |

## 9. Mock servers

| Postman feature | Verbnest | Priority | Notes |
|---|---|---|---|
| Mock server from saved examples | Yes | P2 | Local HTTP server (desktop; Android while app is foreground). Matching by method, path, query, headers, body like Postman. |
| Cloud-hosted mock URLs | — | — | Out of scope; CLI mock mode can be self-hosted. |

## 10. API design & documentation

| Postman feature | Verbnest | Priority | Notes |
|---|---|---|---|
| API Builder (spec editor, versions, linked collections) | Later | P2 | OpenAPI viewer/editor with validation. |
| Generate collection from OpenAPI | Yes | P1 | |
| Contract testing against schema | Yes | P2 | Validate responses against OpenAPI schema. |
| Published documentation | Partial | P2 | Static HTML/Markdown docs export; no hosting. |
| Code generation (cURL, HTTPie, fetch, axios, Python requests, Go, Java OkHttp, C# HttpClient, Dart http/dio, Swift URLSession, Kotlin OkHttp, PHP, Ruby, PowerShell) | Yes | P1 (cURL in P0) | |

## 11. History, import/export, data

| Postman feature | Verbnest | Priority | Notes |
|---|---|---|---|
| History of sent requests with responses | Yes | P0 | Stored in SQLite with retention limits; restore to tab. |
| Import cURL (paste anywhere) | Yes | P0 | Auto-detect when pasting into URL bar. |
| Import Postman collection v2.0/v2.1, environments, globals | Yes | P0 | |
| Import Postman data dump (bulk export) | Yes | P1 | |
| Import OpenAPI/Swagger, HAR, Insomnia, Bruno, Hoppscotch | Yes | P1 (OpenAPI, HAR), P2 rest | |
| Export Postman v2.1, cURL, HAR | Yes | P0 Postman & cURL, P1 HAR | |

## 12. Collaboration & platform

| Postman feature | Verbnest | Priority | Notes |
|---|---|---|---|
| Cloud sync & real-time collaboration | Replaced | P1 | Explicit exchange: `.verbnest` file export/import and YAML snapshots committed to git by the user. No in-app git. |
| Roles, SSO, audit logs, private API network | — | — | Enterprise cloud features; out of scope. |
| Public API Network | — | — | |
| Integrations (Slack, GitHub, Datadog…) | — | — | Via CLI in CI. |
| Settings sync | Partial | P2 | Settings file can live in the workspace. |

## 13. App-level features

| Feature | Verbnest | Priority |
|---|---|---|
| Light / dark / system theme | Yes | P0 |
| Keyboard shortcuts & command palette | Yes | P0 shortcuts, P1 palette |
| Proxy settings (system, custom HTTP/SOCKS, bypass list) | Yes | P1 |
| CA certificates (custom trust store) | Yes | P1 |
| Localisation | Yes | P1 (en first, ARB files) |
| Auto-update | Store-managed | P1 | App stores on mobile/macOS; Sparkle-like updater or store packages on desktop. |
| Plugins / extensions | Later | P2 | Script-based plugins (auth providers, importers) loaded from workspace. |

---

## Verbnest differentiators (not in Postman)

1. **Phone and tablet support** with a native-feeling responsive UI, e.g. test an API from the field, or hit a device-local endpoint on the LAN.
2. **A single portable SQLite workspace file** with lossless export to Postman and git-friendly YAML snapshots.
3. **No account, ever,** for any core feature.
4. **Exact wire view**: raw request bytes as sent, including auto headers.
5. **Shared core between app and CLI**, guaranteeing identical results in CI.
