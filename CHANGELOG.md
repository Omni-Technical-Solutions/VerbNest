# Changelog

Versioning follows `docs/spec/roadmap.md` (Release workflow): feature = major, minor = minor, fix = patch, chore = no version change. The build number is separate and rises with every build (`BUILD_NUMBER`). One version covers the whole workspace.

## 0.12.0

- Secrets are stored in the system secret store (macOS Keychain verified; other platforms not yet tested) through `flutter_secure_storage`. Existing secrets move over on first start. If the store is unavailable, PostIt falls back to the old unencrypted device store and Settings says so.
- Plain variables have a device-local Current value next to the shared Initial value; requests use Current when it is set (FR-VAR-002).
- Show/hide toggle on secret values.
- Fix: collection and folder secret variables now resolve when sending.
- Not yet: `.env` import.

## 0.11.0

- Collection and folder settings page: description, auth, variables (FR-COL-002).
- Warning before send when variables are unresolved, with "Send anyway" and "Don't warn again" (setting) (FR-VAR-006).
- Custom HTTP method entry (FR-HTTP-001).
- Request settings: max redirects, keep method on redirect, strip auth cross-origin, auto-decompress (FR-HTTP-007).
- Duplicate variable names warn in the editor (last wins).
- Not yet: scripts on containers, variable highlighting.

## 0.10.0

- Response viewer: Pretty/Raw toggle, search with match count and highlight, read-only Cookies tab, copy body (FR-RES).
- History: open the original request or save an entry as a new request (secrets stay masked) (FR-HIS-002).
- Theme setting: system, light or dark, saved with the workspace (FR-APP-004).
- Not yet: save/share to file, image preview, FTS5 search, drag and drop.

## 0.9.0

- OAuth 2.0 client credentials and password grants (FR-AUTH-002): `OAuth2Auth` model, token fetch with Basic or body client auth, in-memory token cache, Postman import/export, editor UI.
- Workspace HTTP defaults in Settings (timeout, TLS verification, redirects), stored in the workspace and applied to every request.
- `SecretStore` interface in `postit_storage` with an interim local-database implementation (not encrypted; keychain adapters still to do).
- Keyboard shortcuts: Ctrl/Cmd+Enter sends, Ctrl/Cmd+W closes the tab.
- ADR-001, 002 (proposed), 004, 005; GitHub Actions CI (format, analyze, tests; not yet run on GitHub).
- Not yet: OAuth authorization code/PKCE, OS keychain, theme setting, history retention UI, Phase 0 spikes (scripting engine, platform builds).

## 0.8.0

- New `postit_import` package (FR-IO-001..003):
  - cURL import (`-X -H -d --data-raw --data-binary -F -u -b -k -L -I -G -A -e -m --url`, bundled short flags, quotes, line continuations) and export; unknown options are reported, not fatal.
  - Postman v2.1/v2.0 collection import and export: folders, auth, variables, per-request scripts, raw/urlencoded/form bodies, disabled rows, path variables; unsupported bodies and auth types are kept verbatim and written back. Postman environments and globals import and export (secrets omitted on export by default).
- App: Import dialog (paste cURL or Postman JSON), Copy as cURL, Copy as Postman JSON.
- Not yet: file pickers (import/export use paste and clipboard), `.postit` copy export in the UI (storage `exportCopy` exists), folder/collection scripts and saved examples (dropped with a warning), OpenAPI/HAR (P1).

## 0.7.0

- Environments and history (FR-VAR-002..004, FR-HIS-001/002):
  - Environments and globals page with a variables table; secret variables are never written to the workspace file (values kept in the device-local store until the OS secret store lands).
  - Environment selector and variables quick-look in the request editor; the active environment is remembered per workspace.
  - Every send (and engine failure) is recorded in local history with secrets masked; history page with search, detail view and clear.
- Desktop sidebar now shows only for Collections.
- Not yet: separate current vs initial values for non-secret variables, history retention settings UI.

## 0.6.0

- Request editor (FR-REQ, FR-HTTP-001..007, FR-RES):
  - Method, URL bar, Params (synced with the URL query and `:path` variables), Headers, Auth (inherit/none/bearer/basic/API key), Body (raw languages, urlencoded, form; binary kept but not editable), per-request Settings.
  - Debounced autosave of drafts; renames made in the tree are never overwritten.
  - Send and cancel; variables resolved from global, collection and folder scopes; undefined-variable and unsupported-auth banners.
  - Response viewer: status, time, size, pretty-printed JSON, headers and the masked request as sent.
  - Open-request tab strip on desktop; full-screen editor on phone and tablet.
- Not yet: environments, history recording, multipart file picking, scripts.

## 0.5.0

- App foundations (FR-COL-001/003, FR-WS-001):
  - Riverpod state, default workspace opened in app storage at start-up.
  - Collections sidebar: tree with filter, new collection/folder/request, rename, duplicate, move up/down, delete with confirmation; open-request tabs state.
  - Adaptive layout hosts the tree (sidebar on desktop, full page on phone and tablet).
  - `NodeInfo.method` in storage so the tree shows request methods cheaply.
- Request editor is the next step; selecting a request shows only its name for now.

## 0.4.0

- `postit_http` request pipeline (FR-HTTP-002..007, FR-VAR-006, FR-AUTH-001/006):
  - `RequestBuilder` turns a stored request into a sendable spec: variable substitution, `:path` variables, bearer/basic/API key auth (header or query), raw/urlencoded/multipart/binary bodies, default Content-Type that the user can override, workspace-default plus per-request settings.
  - Reports unresolved variables and unsupported auth types without failing; empty or invalid URLs are build errors.
  - `Masker` hides secret values and sensitive headers in heads, bodies and stored records.

## 0.3.0

- New `postit_storage` package implementing ADR-007 (FR-WS-001, 002, 004, 007, 008; part of FR-HIS-001..003, FR-VAR-002).
  - Workspace database (`.postit`): collection tree with ordering, move (cycle-safe), duplicate and cascading delete; requests with unknown-key preservation; environments, globals, collection/folder variables (secret values never stored); per-request revisions with cap and restore; auth inheritance chain; `VACUUM INTO` export.
  - Safety: application id check, newer-schema rejection without modification, pre-migration backup, exclusive single-writer lock, re-entrant transactions with full rollback.
  - Local database: history with search, body cap, retention; current variable values; recent workspaces.
- `Ulid` generator in `postit_core`.
- Built on `sqlite3` directly rather than drift (see architecture.md §3.3).

## 0.2.0

- `postit_core` domain models: `KeyValue`, `Auth` (inherit, none, API key, bearer, basic, raw passthrough), `RequestBody` (raw languages, urlencoded, form, binary), `HttpRequestItem`, `RequestSettings`, `Scripts`, `Environment`.
- URL helpers for query params and `:path` variables that never decode or rewrite user text (FR-HTTP-003, FR-HTTP-004).
- Auth inheritance resolution (FR-COL-002). Unknown keys and auth types round-trip.

## 0.1.0

- Monorepo scaffold: `postit_core` (variable resolver), `postit_http` (HTTP/1.1 engine), `test_server`, `postit_app` (adaptive shell).
- Spec kit with SQLite workspace storage (ADR-007, proposed).
