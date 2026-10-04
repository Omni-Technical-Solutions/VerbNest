# Changelog

Versioning follows `docs/spec/roadmap.md` (Release workflow): feature = major, minor = minor, fix = patch, chore = no version change. The build number is separate and rises with every build (`BUILD_NUMBER`). One version covers the whole workspace.

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
