# Requirements

Requirement IDs are stable. Priority: **P0** MVP, **P1** v1, **P2** later. Each FR lists acceptance criteria (AC) that become test cases (see testing.md).

---

## 1. Workspaces & storage (FR-WS)

Storage decision: ADR-007. A workspace is a SQLite database file (`.postit`); device-local state lives in a separate local database.

**FR-WS-001 (P0) Create/open workspace.** A workspace is a single `.postit` SQLite file. Users can create a new one (stored in app storage), import a `.postit` file (copied into app storage), or, on desktop, open a `.postit` file in place.
- AC: A file that is not a PostIt database, or has a newer schema version than the app, is rejected with a clear message and left untouched.
- AC: A file with an older schema version is migrated after an automatic backup copy.
- AC (mobile): No folder permission is required for the default flow; import/export use the platform file picker.

**FR-WS-002 (P0) Recent workspaces** list with switcher; last workspace reopens on launch.

**FR-WS-003 (withdrawn)** File watching. Replaced by reactive database queries (UI updates from drift `watch()`); no external file edits to track.

**FR-WS-004 (P0) Single-writer safety.** A workspace open in one PostIt process cannot be opened for writing by another; the second attempt shows "in use" and offers read-only.
- AC: Killing the app mid-write never leaves a half-applied change (transactional); verified by crash-injection tests (NFR-REL-001).

**FR-WS-005 (withdrawn)** Git integration. Replaced by the YAML snapshot workflow (FR-WS-006); in-app git UI is dropped from scope (open-questions.md #7).

**FR-WS-006 (P1) YAML snapshot export/import.** Export a workspace to a folder of YAML files (data-model.md §1.2) with deterministic output so it can be committed to git; import a snapshot into a new workspace or merge into the open one with a conflict list.
- AC: export → import → export is byte-identical; no secret values or current values are written.

**FR-WS-007 (P0) Backup and share.** "Export workspace" writes a consistent `.postit` copy (no history, current values or secrets) and offers the platform share sheet.

**FR-WS-008 (P1) Revision history.** Each saved edit of a request keeps a revision (default last 50); the user can view a diff and restore.

**FR-WS-009 (P0) Sync-folder warning.** When a workspace path is inside a known cloud-sync folder, show a one-time warning that live syncing can corrupt the database and recommend export/import.

## 2. Collections (FR-COL)

**FR-COL-001 (P0)** Create, rename, delete, duplicate collections, folders and requests; drag and drop to reorder/move (long-press drag on touch).
**FR-COL-002 (P0)** Folders and collections carry description, auth, variables and (P1) scripts, inherited by children.
**FR-COL-003 (P0)** Sidebar tree with filter-as-you-type and full-text workspace search (names, URLs, bodies, descriptions).
- AC: Search over 5,000 requests returns in < 150 ms.
**FR-COL-004 (P1)** Favourites/pinned requests.
**FR-COL-005 (P1)** Saved examples (request + response pairs) per request.

## 3. HTTP requests (FR-HTTP)

**FR-HTTP-001 (P0)** Methods: standard set plus free-text custom method.
**FR-HTTP-002 (P0)** URL editor with variable highlighting, autocomplete for `{{` and resolved-value tooltip.
**FR-HTTP-003 (P0)** Query params table, two-way synced with URL; per-row enable; bulk edit.
**FR-HTTP-004 (P0)** Path variables (`:name`) detected and editable.
**FR-HTTP-005 (P0)** Headers table with enable toggles, autocomplete of standard header names and common values, bulk edit; auto-generated headers listed and overridable.
**FR-HTTP-006 (P0)** Body modes: none, form-data (text + file parts), urlencoded, raw (JSON, XML, HTML, text, JavaScript) with matching `Content-Type` auto-set unless overridden, binary (file).
- AC: JSON body with `{{var}}` placeholders is syntax-highlighted without false errors.
**FR-HTTP-007 (P0)** Request settings: timeout, follow redirects (max count), TLS verification, keep original method on redirect, strip auth on cross-origin redirect (default on), auto-decompress.
**FR-HTTP-008 (P1)** HTTP/2 negotiation where platform client supports it (see architecture.md).
**FR-HTTP-009 (P0)** Send / Cancel. Cancel aborts in-flight requests immediately.
**FR-HTTP-010 (P0)** "Final request" view showing resolved URL, all headers actually sent and body bytes.
**FR-HTTP-011 (P1)** Cookie jar per workspace: automatic store/send, manager UI, per-request "don't send cookies".
**FR-HTTP-012 (P1)** Proxy: system, manual HTTP/HTTPS/SOCKS5 with auth, bypass list; per-request override.
**FR-HTTP-013 (P1)** Client certificates per host pattern (PEM+key, PFX/P12 with passphrase) and custom CA bundle.

## 4. Responses (FR-RES)

**FR-RES-001 (P0)** Show status code + reason, total time, size (headers/body, wire/decoded).
**FR-RES-002 (P0)** Body views: Pretty (highlight, fold, line numbers), Raw, Hex (P1), Preview (images P0; HTML/PDF P1).
**FR-RES-003 (P0)** Headers and cookies tabs; copy any value.
**FR-RES-004 (P0)** Search within body; (P1) JSONPath / XPath filter.
**FR-RES-005 (P0)** Save body to file; copy to clipboard; share (mobile).
**FR-RES-006 (P0)** Bodies > 10 MB stream to a temp file; preview shows first 1 MB with "open full".
**FR-RES-007 (P1)** Timing breakdown (DNS, connect, TLS, TTFB, download) and connection info (remote IP, protocol, TLS version, cipher, certificate chain).

## 5. Variables & environments (FR-VAR)

**FR-VAR-001 (P0)** Scopes and precedence: local > data > environment > collection > global. Resolution is recursive (a variable may reference another) with cycle detection.
**FR-VAR-002 (P0)** Each variable has initial value (stored in the workspace database), current value (local database only, never written to the workspace database or exports), type (default | secret), enabled flag, description.
**FR-VAR-003 (P0)** Secret values stored in OS secure storage keyed by workspace+scope+name; masked everywhere with reveal toggle.
**FR-VAR-004 (P0)** Environment selector always visible; quick-look panel listing every variable in scope with resolved value and source.
**FR-VAR-005 (P0)** Dynamic variables: `$guid`, `$timestamp`, `$isoTimestamp`, `$randomInt`, `$randomUUID`, `$randomEmail`, `$randomFirstName`… (P1: full Postman faker list).
**FR-VAR-006 (P0)** Unresolved variables are highlighted before send; sending with unresolved vars shows a warning (dismissible, remember choice).
**FR-VAR-007 (P1)** Per-device overrides: an environment variable's current value overrides its shared initial value on this device only. Optionally import a `.env` file into current values.

## 6. Authorization (FR-AUTH)

**FR-AUTH-001 (P0)** Inherit, None, API Key (header/query), Bearer, Basic.
**FR-AUTH-002 (P0)** OAuth 2.0 client credentials and password grants with token caching.
**FR-AUTH-003 (P1)** OAuth 2.0 authorization code (+PKCE) and implicit, with system browser flow; refresh tokens; token manager listing/deleting tokens.
- AC (desktop): loopback redirect on `http://127.0.0.1:<random>/callback`.
- AC (mobile): custom scheme `postit://oauth/callback` and optional universal link.
**FR-AUTH-004 (P1)** Digest, JWT bearer (HS/RS/ES algorithms), AWS SigV4.
**FR-AUTH-005 (P2)** OAuth 1.0, Hawk, NTLM (desktop), Akamai EdgeGrid, ASAP.
**FR-AUTH-006 (P0)** Auth output is visible in the final request view; secrets masked.

## 7. History & console (FR-HIS)

**FR-HIS-001 (P0)** Every sent request is recorded with resolved request, response (body capped at 1 MB by default), timing, environment name.
**FR-HIS-002 (P0)** History grouped by day, searchable, restorable into a new tab, saveable into a collection.
**FR-HIS-003 (P0)** Retention settings (count and age); clear history; option to not record secrets / bodies.
**FR-HIS-004 (P0)** Network console: chronological log of requests incl. those made by scripts and redirects. (P1) Script `console.log` output.

## 8. Import / export (FR-IO)

**FR-IO-001 (P0)** Import cURL (paste into URL bar auto-detects `curl ` prefix; supports common flags `-X -H -d --data-raw --data-binary -F -u -b -k -L --compressed`).
**FR-IO-002 (P0)** Import Postman collection v2.0/v2.1 including folders, auth, variables, scripts (kept even before scripting ships), examples; environments; globals.
- AC: A corpus of ≥ 20 real-world public Postman collections imports with zero data loss in round-trip (import → export → diff).
**FR-IO-003 (P0)** Export collection to Postman v2.1 and any request to cURL.
**FR-IO-004 (P1)** Import OpenAPI 3.0/3.1 and Swagger 2.0 (folders by tag, examples from schema), HAR, Postman data dump.
**FR-IO-005 (P2)** Import Insomnia v4, Bruno, Hoppscotch; export HAR, OpenAPI (best effort), HTML docs.
**FR-IO-006 (P1)** Code generation for the languages listed in feature-inventory.md §10.

## 9. Scripting & tests (FR-SCR)

**FR-SCR-001 (P1)** Pre-request and post-response scripts at collection, folder and request level, executed in Postman order (collection → folder → request).
**FR-SCR-002 (P1)** `pm` API compatibility (see feature-inventory.md §7). Scripts that use unsupported APIs fail with a clear "not supported" error naming the API.
**FR-SCR-003 (P1)** `pm.test` + Chai BDD `pm.expect`; results in a Tests tab and in runner reports.
**FR-SCR-004 (P1)** Sandbox: no `fs`, no raw sockets; network only via `pm.sendRequest` which goes through the same HTTP engine and appears in the console. Per-script timeout (default 5 s) and memory cap.
**FR-SCR-005 (P1)** Script editor with JS highlighting, `pm.` autocomplete, snippets panel.
**FR-SCR-006 (P1)** No-code assertions builder (status, header, JSONPath, response time, schema) stored as structured data and compiled to script.
**FR-SCR-007 (P2)** Workspace script library (shared JS modules importable by scripts).

## 10. Collection runner (FR-RUN)

**FR-RUN-001 (P1)** Run a collection/folder or a hand-picked list; reorder; iterations; delay; stop on first failure; data file (CSV/JSON) supplying `data` scope.
**FR-RUN-002 (P1)** `pm.execution.setNextRequest` / `skipRequest` flow control.
**FR-RUN-003 (P1)** Live results view; save run; export JUnit XML, JSON, HTML.
**FR-RUN-004 (P2)** Performance mode (desktop): N virtual users, ramp-up, duration; latency percentiles and error rate.
**FR-RUN-005 (P2)** Headless CLI `postit run <path> -e <env> -d <data> --reporters junit,cli` with exit code = failures > 0.

## 11. GraphQL (FR-GQL) — P1

**FR-GQL-001** Query editor with highlighting, variables JSON editor, operation name selection.
**FR-GQL-002** Schema introspection (manual + auto on URL change), cached; autocomplete and validation from schema; schema explorer/docs panel.
**FR-GQL-003** Import schema from SDL file.
**FR-GQL-004 (P2)** Subscriptions over `graphql-transport-ws`.

## 12. WebSocket / Socket.IO / SSE (FR-RT)

**FR-RT-001 (P1)** WebSocket connect with headers, query, subprotocols, auth; message composer (text/JSON/binary base64); saved messages; message log with direction, timestamp, size, search, filter; auto-reconnect option.
**FR-RT-002 (P1)** SSE: open stream, show events (id, event, data, retry) in a log, filter by event type, reconnect with `Last-Event-ID`.
**FR-RT-003 (P2)** Socket.IO v2/v3/v4: emit with event name + args, listen to named events, ack support.
**FR-RT-004 (P1)** On mobile, real-time connections are closed (with a log entry) when the app is backgrounded beyond the OS limit; reconnect offered on resume.

## 13. gRPC and other RPC (FR-RPC) — P2

**FR-RPC-001** Load service definitions via server reflection or `.proto` files (with import paths).
**FR-RPC-002** Unary, server-streaming, client-streaming and bidirectional calls; message editor generated from the descriptor as JSON with field autocomplete and "generate example".
**FR-RPC-003** Metadata (headers), deadlines, TLS/mTLS, compression.
**FR-RPC-004** Status code, trailers, and streaming message log.
**FR-RPC-005** JSON-RPC 2.0 (HTTP and WebSocket), XML-RPC and SOAP request types with templates; WSDL import (P2).
**FR-RPC-006** MQTT 3.1.1/5: connect, subscribe (wildcards), publish with QoS/retain, message log.
**FR-RPC-007 (P2, spike)** MCP client: connect to an MCP server (stdio on desktop, Streamable HTTP everywhere), list tools/resources/prompts, invoke a tool with a JSON-schema-driven form.

## 14. Mock server (FR-MOCK) — P2

**FR-MOCK-001** Start a local mock server for a collection on a chosen port; responses come from saved examples.
**FR-MOCK-002** Matching: method + path (with path vars) + optional query/header/body match; `x-mock-response-name` / `x-mock-response-code` header selection like Postman.
**FR-MOCK-003** Request log of mock hits. Desktop only for background use; Android/iOS while foreground (documented).

## 15. App shell (FR-APP)

**FR-APP-001 (P0)** Light/dark/system theme; font size scaling; editor font choice.
**FR-APP-002 (P0)** Keyboard shortcuts (desktop and hardware keyboards on tablets): send (Ctrl/Cmd+Enter), new request (Ctrl/Cmd+N), save (Ctrl/Cmd+S), close tab, switch tab, search (Ctrl/Cmd+K), toggle sidebar.
**FR-APP-003 (P1)** Command palette.
**FR-APP-004 (P0)** Settings: default timeout, TLS verify default, history retention, editor options, (P1) proxy, certificates, language.
**FR-APP-005 (P1)** Localisation-ready strings (ARB), English shipped; RTL layout support.
**FR-APP-006 (P0)** Crash-safe: unsaved drafts autosaved every 2 s and restored after a crash.

---

## Non-functional requirements (NFR)

| ID | Requirement | Target |
|---|---|---|
| NFR-PERF-001 | Cold start to interactive | < 2 s desktop, < 2.5 s mid-range Android (e.g. Pixel 6a) |
| NFR-PERF-002 | App overhead added to request time | < 5 ms p95 vs. raw `curl` on the same machine |
| NFR-PERF-003 | Editor responsiveness | 60 fps scrolling for 5 MB JSON; < 300 ms to pretty-print 5 MB |
| NFR-PERF-004 | Workspace scale | 10,000 requests, 200 environments without UI lag |
| NFR-MEM-001 | Memory | < 300 MB desktop, < 200 MB mobile with 20 open tabs |
| NFR-SEC-001 | Secret storage | OS keychain/keystore only; never in plaintext files or SQLite |
| NFR-SEC-002 | Script sandbox | No access outside documented `pm` API; fuzz-tested |
| NFR-SEC-003 | Dependency hygiene | Automated vulnerability scanning (OSV) in CI; SBOM per release |
| NFR-PRIV-001 | Telemetry | None by default; opt-in only |
| NFR-A11Y-001 | Accessibility | Semantics on all controls; screen reader verified on TalkBack, VoiceOver (iOS/macOS), Narrator, Orca (best effort) |
| NFR-REL-001 | Data durability | All workspace writes are SQLite transactions (WAL); no corruption or partial edits on crash/power loss; migrations back up the file first |
| NFR-COMP-001 | Postman compatibility | Round-trip import/export of v2.1 with zero semantic loss on the test corpus |
| NFR-PORT-001 | Minimum OS versions | Android 7.0 (API 24), iOS 15, macOS 11, Windows 10 1809+, Ubuntu 22.04 / Fedora 39 (x64 + arm64) |
| NFR-SIZE-001 | Install size | < 40 MB mobile download, < 80 MB desktop installer |
| NFR-I18N-001 | Unicode | Full Unicode in names, URLs (IDN), headers values (per RFC), bodies |
