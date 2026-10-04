# Implementation plan: remaining work after v0.10.0

Status date: 2026-10-04. Each step is one phase-step commit (see roadmap.md, Release workflow). Sizes: S = under a day, M = 1 to 3 days, L = about a week. Steps before 1.0 use `minor`; the MVP release itself is the first `feature` commit (1.0.0).

## Done so far (summary)

Core models, SQLite workspace and local stores, request builder, custom HTTP/1.1 engine, collections tree with CRUD, request editor (params, headers, auth, body, settings), send/cancel, response viewer (pretty/raw, search, cookies, headers, sent), environments, globals, quick-look, history with search and restore, cURL and Postman import/export, OAuth2 client credentials and password, workspace HTTP defaults, theme, shortcuts (send, close tab), macOS DMG packaging, CI workflow.

## Gaps against the P0 requirements (MVP)

| Area | Missing | FR |
|---|---|---|
| Collections | Collection/folder settings page (description, auth, variables) has no UI; drag and drop; full-text workspace search (FTS5); favourites are P1 | COL-001/002/003 |
| Request editor | Variable highlighting, `{{` autocomplete, resolved-value tooltip; header name/value autocomplete; bulk edit; auto-generated headers list; free-text custom method; max redirects, keep-method, strip-auth, auto-decompress in UI; file pickers for form and binary parts | HTTP-001/002/003/005/006/007 |
| Final request | Body bytes are not shown, only the head | HTTP-010 |
| Response | Syntax highlight, fold, line numbers; image preview; save to file and share; streaming of bodies over 10 MB; wire vs decoded size; copy single header value | RES-001..003/005/006 |
| Variables | Current value kept apart from initial value for non-secrets; secrets in the OS secure store (today: unencrypted local DB); reveal toggle; warn before send on unresolved variables with remember choice | VAR-002/003/006 |
| History | Group by day; retention settings; do not record bodies/secrets option; network console | HIS-002/003/004 |
| Import | Paste cURL into the URL bar; Postman examples and folder scripts kept | IO-001/002 |
| Workspace | Open, create and switch workspaces; `.postit` import/export UI; revisions UI; attachments for binary bodies | WS-* |
| App | Font scaling and editor font; shortcuts for new, save, switch tab, search, toggle sidebar; settings for history; open tabs restored after restart | APP-001/002/004/006 |
| Platforms | Only macOS (Intel) has been built. Android, iOS, Windows, Linux builds, entitlements, signing; CI build matrix; Phase 0 spikes; TLS listeners in `test_server`; performance benchmarks | Phase 0 exit, NFR-* |

## Phase 1 completion: steps 9 to 16 (to 1.0.0)

| Step | Scope | Size | Depends on |
|---|---|---|---|
| 9 Container settings and pre-send checks | Collection/folder page: description, auth, variables; unresolved-variable warning before send with "remember"; free-text method; remaining request settings | M | none |
| 10 Secrets and variable values | `flutter_secure_storage` adapter behind `SecretStore`, Linux no-keyring fallback (spike d); reveal toggle; current vs initial values for all variables; `.env` import (P1) | M | decision: plugin choice |
| 11 Editor power features | Variable highlighting and `{{` autocomplete with tooltip; header autocomplete; bulk edit; auto-generated headers listed and overridable; body bytes in final-request view | L | none |
| 12 Files and attachments | File picker plugin; attachments table API in storage; form-data and binary file parts; `FileReader` wiring; save response to file; share on mobile | M | decision: `file_selector`, `share_plus` |
| 13 Response viewer P0 | Spike (c) `re_editor` with 5 MB JSON; highlight, fold, line numbers; image preview; wire/decoded sizes; copy header values; large-body streaming to temp file | L | step 12 |
| 14 Search, reorder, workspaces | FTS5 index and Ctrl/Cmd+K search; drag and drop and long-press drag; workspace open/new/switch; `.postit` import/export UI; revision history UI | L | step 12 |
| 15 History, settings, shortcuts | Group by day; retention and no-bodies options; network console; font scale and editor font; full shortcut set; persist open tabs; paste-cURL detection in URL bar | M | none |
| 16 Platforms and MVP release | Android, iOS, Windows, Linux builds and entitlements; Apple Silicon/universal macOS; CI build matrix; TLS test listeners; spikes (a) to (e) with go/no-go; NFR-PERF checks; then `feature` commit to 1.0.0 | L | steps 9 to 15 |

Exit: all FR-*-P0 complete, Postman corpus round-trips (needs a 20-collection corpus), NFR-PERF-001/002 met, external beta passes.

## Phase 2 (v1.x toward the "v1.0" scope in roadmap.md)

| Step | Scope | Size |
|---|---|---|
| 17 Scripting runtime | ADR-002 spike on five platforms; QuickJS-ng; sandbox, timeouts; `pm` API; Chai; Tests tab; console | L |
| 18 Assertions and runner | No-code assertions; collection runner with data files, flow control, iterations; JUnit/JSON/HTML reports | L |
| 19 Auth P1 | Authorization code, PKCE, implicit via system browser; refresh and token manager; Digest, JWT, AWS SigV4 | L |
| 20 Network features | Cookie jar and manager, proxy (HTTP/HTTPS/SOCKS5), client certificates and custom CA, HTTP/2, timing breakdown and TLS info | L |
| 21 Import/export P1 | OpenAPI/Swagger, HAR, Postman data dump; code generation | L |
| 22 Polish | Saved examples, favourites, command palette, ARB localisation and RTL, YAML snapshot export/import | M |
| 23 Store releases | Play, F-Droid, App Store, Microsoft Store/winget, Flathub; notarisation | L |

## Later phases

- Phase 3: GraphQL, WebSocket, SSE, mobile background handling, JSONPath/XPath filters, hex view.
- Phase 4: gRPC (reflection, descriptors, streaming), `.proto` parser, Socket.IO, MQTT, JSON-RPC, XML-RPC, SOAP, MCP spike.
- Phase 5: headless CLI, mock server, OpenAPI contract validation, plugin API, external secret providers.

## Risks and decisions needed

1. Plugin choices (secure storage, file picker, share, code editor) add native dependencies. Each must be proven on all five platforms before it is accepted.
2. ADR-002 (QuickJS-ng) is unproven on iOS and the other platforms; the Phase 2 schedule depends on that spike.
3. Only macOS Intel has been built, and no step has been run on a real device. Step 16 may uncover platform issues in the engine (sockets, TLS) and in `sqlite3` bundling.
4. Interim secret storage is unencrypted. Do not ship 1.0 without step 10.
