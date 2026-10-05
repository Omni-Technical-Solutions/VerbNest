# Changelog

Versioning follows `docs/spec/roadmap.md` (Release workflow): feature = major, minor = minor, fix = patch, chore = no version change. The build number is separate and rises with every build (`BUILD_NUMBER`). One version covers the whole workspace.

## 0.26.0

- HTTP/2 (FR-HTTP-007): HTTPS requests offer `h2` and `http/1.1` through ALPN and use HTTP/2 when the server picks it. Request Settings has a new "HTTP version" choice: Auto, HTTP/1.1 only, HTTP/2 only. The response shows the protocol. Built on the `http2` package (ADR-008). The "Sent" view for HTTP/2 lists the pseudo-headers and lower-case fields as encoded, not raw bytes. Not done: HTTP/2 over plain `http://`, connection reuse, server push.
- Timing breakdown (FR-RES-005): tap the time in the response status line to see DNS, TCP connect, TLS handshake, waiting (TTFB), download and other time. The engine already measured these; they were not shown before.
- Response filter: JSON bodies take a JSONPath, XML bodies take an XPath. A bad expression shows the reason and keeps the body. Uses the existing JSONPath subset and the `xml` package's XPath.
- Hex view of the response body (first 64 KB).
- Import safety: a file or pasted text over 64 MB is refused with a clear message. New fuzz tests feed mutated Postman, OpenAPI, HAR and cURL input to the importers; they found no crashes.
- CI now runs package tests on Linux, Windows and macOS, and app tests on Linux and Windows. The workflow has still never run.
- New test server listener for HTTP/2 (`test_server/lib/h2_server.dart`).
- Not done: moving the remaining UI strings to ARB (tests build the widgets without localisation delegates, so each screen needs its tests changed too), HTML preview, PDF preview, profiling very large workspaces. Checked with unit and widget tests on macOS, and by hand against `nghttp2.org` and `cloudflare.com` over HTTP/2. Windows and Linux are not verified.

## 0.25.2

- Fix: in right-to-left languages, code and JSON in the response, code generator and similar views, and fields for URLs, headers and variables, were mirrored. They now always read left to right.
- Added `scripts/screenshots_macos.sh`, which renders 18 App Store screenshots (2880x1800) from sample data, and the listing copy in `docs/release/app-store-post.md`.

## 0.25.1

- Security: the OAuth 2.0 sign-in only opens http and https links, so an imported collection cannot make PostIt open a `file:` or app-link URL.
- Security: when a redirect goes to another origin, headers that look like credentials (`X-Api-Key`, `X-Auth-Token`, anything with auth, token, secret, key, session or cookie in its name) are now removed as well, not just `Authorization` and `Cookie`. The existing "strip on cross-origin redirect" setting still controls this.
- Security: writing a snapshot refuses file names that are absolute or contain `..`; reading a snapshot folder does not follow links and refuses files over 256 MB.
- Speed: a response body is decoded once instead of on every screen update, and a large pretty-printed JSON body is formatted once per response instead of on every keystroke in the search box.
- Speed: workspaces get an index on saved examples (schema 2, applied when a workspace is opened), which makes deleting requests and folders faster. Cleaning up unused attachments at open is now one pass over the data instead of one search per attachment.
- Reviewed and unchanged: database queries all use bound parameters; scripts have no file or network access and are limited to 64 MB and 5 s; the OAuth redirect listener binds to the local machine only and checks `state`; secrets stay masked in history and the console.
- Not done: no fuzzing of the importers, no limit on the size of an imported file in the UI, and no profiling with very large workspaces (tested with unit tests only).

## 0.25.0

- Language setting (FR-APP-005): Settings, "Language" picks System default, English or Arabic, and is remembered in the workspace. The Settings page text is translated; other screens still have fixed English text, and the Arabic is a draft that a native speaker has not reviewed.
- Postman saved responses are now imported as examples and written back on export (they were dropped before).
- Script editor: JavaScript syntax colours (keywords, strings, numbers, comments, `pm` and `console`) and `pm.` / `console.` completion chips while typing. No full parser, so it only colours and suggests.
- Internal clean-up with no behaviour change: snapshot import, cURL parsing, the collection runner loop and request sending were split into smaller steps.
- Checked with unit and widget tests on macOS; not tried by hand.

## 0.24.0

- Favourites (FR-COL-004): star a request in the editor or from its menu; starred requests show a star in the tree, and a header button shows only favourites.
- Saved examples (FR-COL-005): "Examples" in the request editor saves the current response (status, headers, body) with the request, and lists, shows and deletes them.
- Command palette (FR-APP-003): Ctrl/Cmd+K, type to find commands or any request. Workspace search is now Ctrl/Cmd+Shift+F.
- YAML snapshot export and import (FR-WS-006), desktop only: Workspaces, "Export snapshot…" writes a folder of YAML files that gives the same bytes every time, so it diffs cleanly in git. "Import snapshot…" merges by id into the open workspace and keeps anything already there.
- Localisation-ready strings (FR-APP-005): ARB files and generated code are set up with English and an Arabic first draft for the navigation and palette. Layout paddings and alignments now follow the text direction, so right-to-left languages mirror.
- Not done: most screens still have fixed English text, there is no language setting (the device language is used), the Arabic draft has not been reviewed by a native speaker, and snapshots cannot be imported or exported on phones. Checked with unit and widget tests on macOS; the folder picker was not used by hand.

## 0.23.0

- Import OpenAPI 3.0/3.1 and Swagger 2.0 (JSON or YAML) (FR-IO-004): one folder per tag, a `baseUrl` variable from the server, query, header and path parameters, request bodies with example values built from the schema, and the first security scheme (basic, bearer, API key) as the collection's auth. Optional parameters are listed but switched off.
- Import HAR captures: one request per entry.
- Import a single JSON file with `collections` and `environments` lists (Postman backup shape).
- Generate code (request menu, "Generate code…"): cURL, JavaScript (fetch), Python (requests) and Dart (http). Variables stay as `{{names}}` unless you switch on "Fill in variable values".
- Not done: references to other files, per-operation security, OAuth 2.0 schemes, Postman's zip data dump (unzip it and import the files), OpenAPI and HTML docs export. Tested with unit tests only; not tried on large real specs.

## 0.22.0

- Cookie jar (FR-HTTP-011): cookies from `Set-Cookie` are saved per workspace on this device and sent to matching requests, also across redirects. Domain, path, Secure, Max-Age and Expires are honoured. Manage them in Settings, Cookies: delete one, a domain or all. A request can turn this off in its Settings tab.
- Proxy (FR-HTTP-012): HTTP proxy (plain requests and CONNECT tunnels for HTTPS) and SOCKS5, both with optional user name and password, plus a no-proxy host list. Optionally read `HTTP_PROXY`, `HTTPS_PROXY`, `ALL_PROXY` and `NO_PROXY` from the environment. A request can bypass the proxy. With SOCKS5 the proxy resolves the host name.
- Certificates (FR-HTTP-013): add trusted CA certificates and client certificates (PEM with key, or PKCS#12) for chosen hosts. Private keys, passphrases and the proxy password go to the secret store. After a secure response, tap TLS to see the subject, issuer, validity, protocol and whether a client certificate was sent.
- Not done: HTTP/2, the operating system's own proxy settings, PAC files, NTLM/Kerberos proxies. Checked with `dart test` on macOS only; the Settings screens were not tried by hand. Windows and Linux are not verified.

## 0.21.0

- OAuth 2.0 authorization code (with or without PKCE S256) and implicit grants through the system browser (FR-AUTH-003). The redirect is `http://127.0.0.1:<random port>/callback`, received by a short-lived local listener; the state value is checked, the sign-in can be cancelled, and it times out after 5 minutes.
- Refresh tokens: an expired token with a refresh token is renewed without the browser; if the server refuses it, the browser sign-in runs again.
- Token manager ("Tokens…" in the OAuth 2.0 auth editor) lists the tokens kept for this session and deletes them. Token values are never shown. Tokens are not saved to disk.
- Digest auth (MD5 and SHA-256 families, `auth` and `auth-int`): the request is sent once, then re-sent with the computed header after a 401 challenge (FR-AUTH-004).
- JWT bearer with HS256, HS384 and HS512; the payload may use variables, `iat` is added when missing.
- AWS Signature V4 (header signing, optional session token). Checked against the AWS test-suite vectors.
- Postman import/export covers digest, awsv4, jwt, authorization code (PKCE or not) and implicit.
- Authorization, `X-Amz-Security-Token` and secrets stay masked in the console, history and sent view.
- New dependency: `url_launcher` (opens the browser) and `crypto`. Checked to build and run the loopback tests on macOS, the iOS 18 simulator and the Android x86_64 emulator.
- Not done: JWT with RS/ES algorithms, a fixed redirect URL option and the mobile custom-scheme redirect (loopback is used on all platforms), query-string SigV4 and chunked S3 payload signing, device code flow. The real browser launch and a real identity provider were not tested; the sign-in tests drive the redirect in-process. Windows and Linux are not verified.

## 0.20.0

- No-code assertions (FR-SCR-006): status, header, JSON path, response time, body and JSON schema checks with equals, comparison, exists, contains and regex operators. Built in the new Assertions tab; values may use `{{variables}}`. Results show in the Tests tab with `pm.test` results.
- JSONPath subset (`$`, `.key`, `['key']`, `[n]`, `[-1]`, `[*]`, `.*`, `..key`) and a JSON Schema subset; unsupported syntax gives a clear error.
- Collection runner (FR-RUN-001/002): "Run…" on a collection or folder. Pick and reorder requests, set iterations and delay, stop on first failure, stop at any time, and use a CSV or JSON data file (one row per iteration, available as `{{name}}` and `pm.iterationData`). Results appear live.
- `pm.execution.setNextRequest(name | null)` and `pm.execution.skipRequest()` (pre-request only) control a run; `pm.iterationData` is read only. A jump to an unknown name ends the run with an error; a run stops after 10,000 steps.
- Run reports (FR-RUN-003): export JSON, JUnit XML and HTML.
- Assertions are evaluated in Dart, not compiled to JavaScript, so they work and are tested without the script engine.
- Not done: saved run history, parallel runs, running from the command line, cookie jar between iterations. The runner UI was not exercised by widget tests or by hand; the logic is covered by unit tests and the new `pm.execution` script test passes on macOS only (not re-run on iOS or Android). Windows and Linux are not verified.

## 0.19.0

- Scripting: pre-request and post-response scripts on requests, folders and collections, run collection → folder → request (FR-SCR-001). Engine: QuickJS through `fjs` (ADR-002).
- `pm` API: `pm.variables`, `pm.environment`, `pm.collectionVariables`, `pm.globals` (get/set/unset/has/replaceIn/toObject), `pm.request` (method, url, headers, body; editable before sending), `pm.response` (code, status, headers, text(), json(), responseTime, `to.have.status/header`, `to.be.ok`...), `pm.info`, `pm.test`, `pm.test.skip`, `pm.expect` with a Chai subset, `console.*`, and the old `postman.*` and `tests[]` forms.
- Not supported yet, and reported by name: `pm.sendRequest`, `pm.cookies`, `pm.visualizer`, `pm.execution`, `pm.iterationData`, `require`.
- Variable changes made by scripts are stored as current values, so initial (shared) values stay unchanged; new names are created in the scope.
- Sandbox: no files, sockets, `fetch` or timers; 5 s timeout and 64 MB memory cap per script; an infinite loop is stopped.
- Scripts tab on requests and on collection/folder settings; Tests tab in the response (pass/fail counts, messages, script errors, console output).
- A failing pre-request script stops the send; a failing post-response script keeps the response and shows the error.
- CI installs Rust for the builds that compile the script engine.
- Not done: script editor highlighting and `pm.` completion, snippets panel, no-code assertions, `pm.sendRequest`, async scripts, runner reports. Windows and Linux are not verified.

## 0.18.0

- Android: INTERNET permission and cleartext HTTP allowed (an API client must reach `http://` hosts); release APK builds (debug-signed, 61 MB, all ABIs).
- iOS: local network usage description; unsigned release/debug build works.
- macOS release binary is universal (x86_64 + arm64).
- CI: build matrix for Linux, Windows, macOS, Android and iOS, with integration tests on desktop (not run yet; the workflow has never executed).
- Test server can listen on TLS (self-signed localhost certificate made with openssl at test time; those tests skip without it); engine tests cover rejecting and accepting it.
- Integration tests `platform_test.dart`: FTS5 search, loopback request, 10,000-request workspace timings, request overhead.
- Not done: Windows and Linux were not built or run; iOS only ran in the simulator; no physical devices. This is not the 1.0.0 release.

## 0.17.0

- Console page: the last 200 requests of this session with the sent and received headers (secrets masked), cleared on exit.
- History is grouped by day and pruned by age and count; settings for days kept, maximum entries, and whether bodies are recorded (FR-HIS-001..004).
- Appearance settings: interface text scale and code font size, stored on this device.
- Shortcuts: Ctrl/Cmd+N new request, +S save now, +\\ toggle sidebar, Ctrl+Tab / Ctrl+Shift+Tab switch tab (plus Send, Search, Close tab from before).
- Open tabs are restored after a restart.
- Pasting a cURL command into the URL bar fills in the whole request.
- Not tested on a device: shortcuts on Windows/Linux, text scale with system accessibility settings on mobile.

## 0.16.0

- Workspace search (Ctrl/Cmd+K or the search button): names, URLs, methods, descriptions, header names and bodies; header values are not searched (FR-COL-003).
- Drag and drop in the sidebar (long press to drag): move into a folder or collection, drop before a request, reorder collections (FR-COL-001).
- Workspaces: switch between recent workspaces, create, rename, import and export `.postit` files (FR-WS-002..007). Imported copies get their own id.
- Earlier versions of a request can be listed and restored (FR-WS-008).
- Unsaved edits are saved when a tab or workspace closes.
- Not yet tested on touch devices or non-macOS platforms.

## 0.15.0

- Response body viewer rewritten: line numbers, JSON colours, fold/unfold of objects and arrays, search highlight, selectable text, virtualised so large bodies scroll (FR-RES-001..003).
- Image preview for PNG/JPEG/GIF/WebP responses.
- Response size shows the size on the wire when it differs from the decoded size.
- Response headers list with a copy-value button per header.
- Not yet: streaming bodies over 10 MB to disk, XML/HTML colours, hex view; render speed on a real 5 MB body was not measured.

## 0.14.0

- Files in requests: form-data file parts and a binary body mode with a file picker. Files are stored inside the workspace, so they travel with it (FR-HTTP-005/006).
- Save the response body to a file (desktop) or share it (mobile) (FR-RES-005).
- Attachment storage API; unused attachments are cleaned up at startup.
- macOS: user-selected file access entitlement.
- Not yet tested: the picker, save dialog and share sheet on any platform; very large files are held in memory.

## 0.13.0

- `{{variables}}` are highlighted in the URL, params, headers, form fields and raw body: defined ones in the theme colour, undefined ones underlined in red (FR-VAR-004).
- With the caret in a variable, a line shows its resolved value and scope (secrets stay hidden); typing `{{` offers matching variable names.
- Header name and Content-Type value suggestions.
- Bulk edit (`key: value` lines, `//` disables) for params, headers and url-encoded bodies.
- Headers tab lists the headers PostIt adds itself; adding the same header overrides it.
- The Sent tab now shows the request body as sent (masked, capped at 64 KB) (FR-HTTP-010).
- Not yet: hover tooltips, code-editor features (folding, line numbers).

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
