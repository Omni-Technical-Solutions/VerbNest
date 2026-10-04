# Architecture & Tech Stack

## 1. Goals that drive the architecture

1. **Same behaviour in app and CLI** → protocol, scripting, variables and runner are pure Dart packages (constitution IV).
2. **Wire fidelity and timing** → PostIt owns its HTTP engine instead of relying solely on `package:http` (constitution V).
3. **Five platforms, one codebase** → platform specifics isolated behind interfaces (constitution III).
4. **Plain files as source of truth** → storage layer writes YAML files; SQLite is only an index/cache (constitution II).

Flutter **web is out of scope**: browsers cannot open raw sockets, set forbidden headers (`Host`, `Cookie`, `Origin`…) or bypass CORS, which defeats the purpose of an API client. Revisit only with a companion "agent" process (open-questions.md).

## 2. Layered view

```
┌────────────────────────────────────────────────────────────────────┐
│ apps/postit_app (Flutter)                                          │
│   presentation: screens, adaptive layouts, widgets, editors         │
│   application: Riverpod controllers / notifiers, use cases          │
├────────────────────────────────────────────────────────────────────┤
│ apps/postit_cli (dart compile exe)                                 │
├────────────────────────────────────────────────────────────────────┤
│ Pure Dart packages (no Flutter import)                              │
│  postit_core      models, variable resolver, auth signers, faker    │
│  postit_http      HTTP/1.1 + HTTP/2 engine, cookies, proxy, TLS     │
│  postit_realtime  WebSocket, SSE, Socket.IO                         │
│  postit_graphql   introspection, schema cache, validation           │
│  postit_rpc       gRPC (dynamic protobuf), JSON-RPC, SOAP, MQTT     │
│  postit_script    JS runtime binding (QuickJS-ng via FFI), pm API   │
│  postit_runner    collection runner, reporters                      │
│  postit_io        importers/exporters, codegen                      │
│  postit_storage   workspace file format, drift (SQLite) index       │
│  postit_mock      local mock server                                 │
├────────────────────────────────────────────────────────────────────┤
│ Platform services (interfaces in core, impls in app / cli)          │
│  SecretStore · FilePicker · FolderAccess · Browser/OAuth launcher   │
│  NativeHttpAdapter (optional) · Clipboard · Share · BackgroundTasks │
└────────────────────────────────────────────────────────────────────┘
```

Repository layout: a single monorepo using **Dart pub workspaces** (Dart ≥ 3.6) with **melos** for scripts.

```
postit/
  apps/postit_app/        Flutter app (android, ios, linux, macos, windows)
  apps/postit_cli/
  packages/postit_*/      as above
  native/quickjs/         QuickJS-ng sources + build hook
  test_server/            local echo/protocol test server (Dart) used by all tests
  docs/adr/  docs/spec/   (this kit)
```

## 3. Key design decisions

### 3.1 HTTP engine (`postit_http`)
- **Default engine:** custom client built on `dart:io` `Socket`/`SecureSocket`, which work on all five native platforms.
  - HTTP/1.1 implemented in-house so PostIt can (a) preserve header order and casing exactly, (b) send custom methods and non-standard headers, (c) record raw request/response bytes, (d) measure DNS (`InternetAddress.lookup`), TCP connect, TLS handshake, TTFB and download separately.
  - HTTP/2 via the official `package:http2` over `SecureSocket` with ALPN `h2`; fallback to HTTP/1.1.
  - Connection pooling per (scheme, host, port, proxy, client-cert) key; keep-alive; gzip/deflate/br decoding (`brotli` via `es_compression` or a pure-Dart decoder).
  - Proxies: HTTP CONNECT and SOCKS5 implemented in the engine; system proxy discovery per platform through the platform service.
- **Optional "system networking" adapter** (`NativeHttpAdapter`): `cupertino_http` (NSURLSession) on iOS/macOS and `cronet_http` on Android, selectable per workspace. Use cases: corporate VPN/proxy auto-config, user-installed CA certificates on Android, HTTP/3. Trade-off shown in UI: fewer timing details and header-casing fidelity.
- Why not `dart:io` `HttpClient` alone: it lower-cases header names unless explicitly preserved, merges some headers, hides raw bytes and gives no timing breakdown.

### 3.2 Scripting (`postit_script`)
- **Engine:** QuickJS-ng (ES2023, small, interpreter-only so it is allowed on iOS where JIT is not) compiled per platform with **Dart build hooks / native assets** and bound via `dart:ffi`. One engine on all platforms gives identical semantics; avoid `flutter_js`, which mixes JavaScriptCore and QuickJS and has uncertain maintenance.
- Runs in a dedicated **isolate** per execution context with a time limit (interrupt handler) and memory limit (`JS_SetMemoryLimit`).
- `pm` API implemented as a JS prelude plus host functions for: variable get/set, `sendRequest` (async bridge back to `postit_http`), cookies, console.
- Bundled libraries (pre-compiled to bytecode at build time): chai, lodash, crypto-js, uuid, ajv, moment/dayjs, cheerio (P2), xml2js (P2).
- App Store note: scripts are user-authored and run in an interpreter, the same model as Scriptable/Pythonista; no code is downloaded from the network.

### 3.3 Storage (`postit_storage`)
- Workspace files: YAML (see data-model.md) parsed with `yaml` and written with `yaml_edit` to keep comments/order stable for clean git diffs.
- Writes are atomic (temp file + rename) and serialised through a single writer per workspace.
- **drift** (SQLite via `sqlite3` with bundled native library) for: history, run results, FTS5 search index, UI state (open tabs, layout), OAuth token cache metadata (tokens themselves in SecretStore).
- File watching with `package:watcher` on desktop; on mobile, rescan on resume (mtime/hash diff).

### 3.4 State management & navigation
- **Riverpod** (v3, code-gen) for dependency injection and state; immutable models via **freezed**; JSON via **json_serializable**.
- **go_router** with `StatefulShellRoute` for mobile; desktop uses a single shell with tab/pane state rather than routes.
- Undo/redo per editor tab via command stack in the tab controller.

### 3.5 Secrets
- `flutter_secure_storage`: Keychain (iOS/macOS), Android Keystore-backed EncryptedSharedPreferences / DataStore, Windows Credential Manager (DPAPI), libsecret on Linux.
- Linux fallback when no Secret Service is running (headless, some tiling WMs): encrypted file (`AES-GCM`, key from user passphrase via Argon2id) with a one-time prompt.
- CLI reads secrets from env vars (`POSTIT_SECRET_<NAME>`) or a passphrase-protected file.

### 3.6 OAuth 2.0 browser flows
- Desktop: open system browser (`url_launcher`) and listen on a loopback `HttpServer` at `127.0.0.1:<random port>`; also support a fixed callback URL by embedding a webview (`webview_all`/`desktop_webview_window`) when the provider forbids loopback.
- Mobile: `flutter_web_auth_2` (ASWebAuthenticationSession / Custom Tabs) with `postit://oauth/callback`.
- Token manager stores tokens in SecretStore keyed by auth config hash.

### 3.7 gRPC
- Transport: `package:grpc` client channel with a custom codec that passes raw bytes.
- Messages: PostIt implements a **descriptor-driven dynamic protobuf codec** (JSON ⇄ proto3 wire format) because Dart's `protobuf` package requires generated classes.
- Service discovery: server reflection (v1 and v1alpha) first; `FileDescriptorSet` (`.pb`/`.binpb`) import second; pure-Dart `.proto` parser third (Phase 4b). Desktop may optionally shell out to `protoc` if found on PATH.

### 3.8 Real-time protocols
- WebSocket: `dart:io` `WebSocket` (all native platforms) with custom headers; raw frame logging via `web_socket_channel` adapters.
- SSE: in-house parser over the HTTP engine's streaming response.
- Socket.IO: `socket_io_client`. MQTT: `mqtt_client` (`mqtt5_client` for v5).

### 3.9 Editors & large content
- Code editor: **re_editor** (virtualised, handles multi-MB text; used in production by the Flutter API tool Reqable) with **re_highlight** for syntax highlighting; custom language mode for `{{var}}` overlays.
- JSON tree view: virtualised `ListView` over a flattened node list built in an isolate.
- Hex view: virtualised rows.
- Pretty-printing and parsing of large bodies happen in a background isolate (`Isolate.run`).

## 4. Flutter package shortlist

| Concern | Package | Notes |
|---|---|---|
| State / DI | `flutter_riverpod`, `riverpod_generator` | |
| Models | `freezed`, `json_serializable` | |
| Routing | `go_router` | |
| DB | `drift`, `sqlite3`, `sqlite3_flutter_libs` (or sqlite3 native-assets build) | FTS5 enabled |
| Secure storage | `flutter_secure_storage` | Linux fallback in-house |
| Files | `file_picker`, `path_provider`, `watcher`, `share_plus`, `desktop_drop` | |
| Folder access (mobile) | `saf` style plugin on Android (or in-house MethodChannel); security-scoped bookmarks on iOS/macOS via in-house plugin | Evaluate `macos_secure_bookmarks` |
| Desktop windowing | `window_manager`, `multi_split_view`, `menu_bar`/`PlatformMenuBar` (macOS native menu) | |
| Editor | `re_editor`, `re_highlight` | |
| Markdown | `flutter_markdown` (or `markdown_widget`) | |
| HTML/PDF preview | `webview_flutter` (mobile, macOS), `webview_windows`, `webview_cef`/`desktop_webview_window` (Linux); `pdfrx` for PDF | Linux webview is the weakest link; fallback to "open in browser" |
| HTTP | `http2`, (opt.) `cupertino_http`, `cronet_http` | Engine is in-house |
| Crypto / signing | `crypto`, `pointycastle`, `dart_jsonwebtoken`, `cryptography` | AWS SigV4, JWT, Digest, Hawk in-house on top |
| OAuth | `flutter_web_auth_2`, `url_launcher`, `oauth2` (parts) | |
| GraphQL | `gql`, `graphql_parser`-based tooling | Introspection client in-house |
| gRPC | `grpc`, `protobuf` (descriptor types only) | Dynamic codec in-house |
| Realtime | `web_socket_channel`, `socket_io_client`, `mqtt_client`, `mqtt5_client` | |
| YAML | `yaml`, `yaml_edit` | |
| CSV | `csv` | Runner data files |
| Fake data | in-house `$random*` set (avoid heavy deps) | |
| i18n | `flutter_localizations`, `intl`, ARB | |
| Logging | `logging` | |
| Lints | `very_good_analysis` or `flutter_lints` + custom | |

Each package is evaluated for: licence compatible with Apache-2.0, maintained in last 12 months, supports all five platforms. Any package failing a platform gets an in-house fallback or a documented limitation.

## 5. Per-platform constraints

### Android
- Min SDK 24, target latest. Permissions: `INTERNET`, `ACCESS_NETWORK_STATE`; `FOREGROUND_SERVICE` + `FOREGROUND_SERVICE_SPECIAL_USE` (or `DATA_SYNC`) only for long collection runs / mock server, with Play policy justification.
- Cleartext HTTP: `android:usesCleartextTraffic="true"` and a network security config allowing user CAs, because testing `http://` and local endpoints is core. (Applies to the native adapter; the `dart:io` engine uses its own trust settings, and PostIt's custom CA feature covers user CAs.)
- Emulator → host machine is `10.0.2.2`; surface a hint when users type `localhost`.
- Folder access via Storage Access Framework; plain paths only inside app storage.
- Background: OS may kill sockets when backgrounded; runner uses a foreground service with notification.
- F-Droid build flavour: no Google Play Services (use embedded Cronet or skip native adapter).

### iOS / iPadOS
- Min iOS 15. `NSLocalNetworkUsageDescription` (and Bonjour keys if discovery is added) required to reach LAN hosts; first LAN request triggers the system prompt.
- ATS does not govern raw sockets, but the native adapter (NSURLSession) needs `NSAllowsArbitraryLoads` with App Review justification ("developer tool for testing arbitrary APIs").
- No background execution for long runs: runs pause when backgrounded (use `beginBackgroundTask` for ~30 s grace). Mock server works only in foreground.
- Files: document picker + security-scoped bookmarks for external workspaces; iCloud Drive folders work as a sync path.
- iPad: full desktop-class layout, pointer and hardware keyboard shortcuts, Stage Manager multi-window (P2).

### macOS
- Min macOS 11. Mac App Store build is sandboxed: entitlements `network.client`, `network.server` (OAuth loopback, mock server), `files.user-selected.read-write`, `files.bookmarks.app-scope`. Direct-download build (notarised DMG) unsandboxed so `git` and `protoc` from PATH are usable; App Store build disables shell-out features.
- Native menu bar via `PlatformMenuBar`; Cmd shortcuts.
- Universal binary (arm64 + x64).

### Windows
- Windows 10 1809+ x64 and arm64. Packaging: MSIX (Store + sideload) and an Inno Setup/WiX `.exe` installer; winget manifest.
- Listening sockets (mock server, OAuth loopback on non-loopback interfaces) trigger the firewall prompt; loopback-only listeners avoid it.
- Credential Manager limits secret size to ~2.5 KB; large secrets (certs) are chunked or stored DPAPI-encrypted in app data.
- System proxy via WinINet settings (read through a small FFI call).

### Linux
- x64 and arm64; GTK3 runner. Packages: Flatpak (Flathub, primary), AppImage, `.deb`, `.rpm`; Snap optional.
- Secret storage needs libsecret + a Secret Service (GNOME Keyring/KWallet); fallback described in §3.5.
- Flatpak sandbox: workspace folders via the file chooser portal (`--filesystem` minimal); `git` invocation through `flatpak-spawn --host` is not allowed on Flathub, so git features use a bundled `git` in the Flatpak.
- Webview support is the weakest; HTML preview falls back to "open in browser" if no webview backend loads.
- Wayland and X11 both supported (Flutter GTK embedder).

## 6. Cross-cutting concerns

- **Concurrency:** UI isolate stays light; network I/O is async on the main isolate (Dart I/O is non-blocking), CPU-heavy work (pretty print, large JSON parse, script execution, import of big files, runner) in worker isolates.
- **Error model:** sealed `PostItError` hierarchy (network, TLS, timeout, script, resolution, storage) with user-facing message, technical detail and remediation hint.
- **Logging:** structured logs to a rotating file in app support dir; no request bodies or secrets in logs.
- **Security:** dependency audit in CI, SBOM (CycloneDX) per release, signed builds (Apple notarisation, Windows Authenticode, Android Play signing, Flatpak GPG).
- **Extensibility (P2):** plugin API in JS (same QuickJS runtime) for auth providers, importers, dynamic variables and response visualisers, loaded from `<workspace>/.postit/plugins/`.

## 7. ADRs to write first

1. ADR-001 Custom HTTP engine over `dart:io` sockets (vs. `HttpClient` / native stacks).
2. ADR-002 QuickJS-ng via FFI as the single script engine.
3. ADR-003 YAML one-request-per-file workspace format.
4. ADR-004 Riverpod + freezed as state architecture.
5. ADR-005 No Flutter web target.
6. ADR-006 Dynamic protobuf codec for gRPC.
