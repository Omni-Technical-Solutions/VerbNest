# Security review and complexity plan (0.65.0)

Written 2026-10-21 against `main` at 0.65.0+51. It reviews the app and its packages for security problems and for code complexity, then plans the work in small steps that keep the tests green. It changes no code.

How it was done: reading the code on the trust boundaries (HTTP engine, redirects, TLS, scripts, imports, snapshots, storage, OAuth, mock server, platform manifests, CI), `scripts/complexity_report.py`, line, class and function counts, and a pattern and history scan for secrets (gitleaks 8.30.1: one reviewed false positive). It is a review by reading, not a penetration test or a fuzzing run; see "Not covered".

## 1. Security

### 1.1 What is already sound
- Redirects: credentials never cross origins (`Authorization`, `Proxy-Authorization`, `Cookie` are always dropped; custom headers are dropped unless on a safe list), even when a request asks not to strip them (`packages/verbnest_http/lib/src/engine.dart`).
- Response bodies are capped while streaming (see S4 for the size of the cap).
- OAuth 2.0 uses PKCE (S256), a random `state` checked on the loopback redirect, `Random.secure()`, and a loopback-only receiver.
- The mock server binds to loopback and refuses requests whose `Host` is not a loopback name (DNS rebinding), with a request size limit.
- Secrets live in the OS keychain or keystore through `VaultSecretStore`; a failed vault write keeps the value in memory only, never on disk. History and the console store masked values.
- SQL is parameterised; the one interpolated fragment is a constant column list; full-text queries are quoted.
- Snapshot export rejects absolute paths, `..`, `.git`, drive letters, NUL and symlink escapes; imports have a 64 MB cap and YAML node and depth limits.
- HTML preview uses a renderer with no scripting, and taps are swallowed (`onTapUrl` returns true).
- App scripts run in QuickJS with no host modules, a 64 MB limit, a 512 KB stack and a 5 s timeout; scripts are off until trusted per workspace.
- macOS release entitlements are minimal (sandbox, network client and server, user-selected files). The build is notarised and uses the hardened runtime.
- Repository: gitleaks in CI, secret scanning and push protection, Dependabot alerts and security updates, actions pinned by SHA, DCO check, protected `main`.

### 1.2 Findings

| ID | Severity | Finding | Evidence | Fix |
| --- | --- | --- | --- | --- |
| S1 | Medium | **Android Auto Backup is on.** The manifest has no `allowBackup` or data extraction rules, so the workspace database (collections, history with bodies) can be copied to Google Drive and to a new device. This contradicts "stays on your device". | merged release manifest: no `allowBackup`; only `usesCleartextTraffic` | `android:allowBackup="false"` plus `dataExtractionRules` and `fullBackupContent` that exclude the app's databases and files; document that workspaces move by snapshot export. Test: a unit check on the manifest, like `macos_renderer_test.dart`. |
| S2 | Medium | **History keeps request and response bodies by default** (`historyBodies = true`) in an unencrypted local SQLite file. Bodies often hold tokens and personal data that are not "secret variables" and so are not masked. | `apps/verbnest_app/lib/src/state/prefs.dart` | Default to off on mobile (or off everywhere with a clear first-run choice), shorter default retention, "Clear history" reachable from Settings, and a note that history is not encrypted. Optional later: encrypt the history table with a key kept in the keychain. |
| S3 | Medium | **The CLI script runtime is Node `vm`**, which is not a security boundary. It is hardened with `--permission` only when the installed Node supports it, and runs without it otherwise. An imported collection's scripts (with `--scripts`) could then escape the context and run code. | `packages/verbnest_script/lib/src/script_engine.dart` (`ProcessScriptEngine`) | Refuse to run scripts when the permission model is unavailable unless `--unsafe-node-scripts` is passed, with a clear message; or run the same QuickJS engine as the app in the CLI (the `fjs` package) and drop Node. Add a test with a fake Node without `--permission`. |
| S4 | Low to Medium | **512 MB response cap.** A hostile or buggy server can make the app hold a very large body in memory, and then pretty-print, search or build a table from it. On phones this means the OS kills the app. | `maxBodyBytes = 512 * 1024 * 1024` in `packages/verbnest_http/lib/src/models.dart` | Lower the default (for example 100 MB desktop, 50 MB mobile), make it a setting, and spill larger bodies to a temporary file with a "Save to file" action; keep the existing 256 KB and 5 MB limits for pretty-printing and tables. |
| S5 | Low | **No explicit CI token permissions.** `ci.yml` has no `permissions:` block, so the `GITHUB_TOKEN` gets the organisation default, which may be write access. | `.github/workflows/ci.yml` | Add `permissions: contents: read` at the top (jobs that need more ask for it); set the organisation default to read-only. |
| S6 | Low | **Native supply chain is not scanned.** Dart packages get Dependabot and licence review, but the 374 Rust crates behind `fjs` and the PDFium build are not scanned for advisories. | `THIRD_PARTY_NOTICES.md`, no `cargo audit` or OSV step | Add an OSV-Scanner (or `cargo audit` and `cargo deny`) job on a schedule and on lockfile changes; pin the `fjs` version and review its changelog on each bump. |
| S7 | Low | **Android `usesCleartextTraffic="true"`.** Probably unnecessary: Dart's `dart:io` sockets are not governed by the Android cleartext policy, so the flag only loosens it for other components (web views, plugins). | `AndroidManifest.xml` | Verify on a device that http:// to a LAN host still works with `false`, then remove the flag or scope it with a network security config. |
| S8 | Info | PDF preview parses untrusted PDFs in-process with PDFium (memory-safety risk by nature). | `pdfrx` | Keep `pdfrx` current (Dependabot) and cap the size of a PDF that is rendered. |
| S9 | Info | `history_recorder.dart` and `editor_state.dart` swallow history write errors (`catch (_)`). Harmless, but a failing history is invisible. | the two files | Log once per session to the console (no secrets) and surface "History could not be saved" in Settings. |
| S10 | Info | 137 unchecked `as` casts in model parsing. A malformed workspace or import can throw instead of reporting a clear error. Imports are wrapped, so this is robustness, not a hole. | `grep " as [A-Z]"` | Parse through small typed readers (`readString`, `readList`) that raise `FormatException` with the path; add fuzz-style tests (see 3, step R7). |

Severity is for a local-first client: nothing here is remotely exploitable without the user opening a hostile server, collection or file.

### 1.3 Not covered
Dynamic testing (fuzzing the importers, the HTTP/2 and WebSocket parsers, the cookie jar), iOS and Linux packaging specifics, the Flatpak and `.deb` sandboxes, Windows installer behaviour, and a threat model for team or sync features (none exist). A fuzzing round is step R7.

## 2. Complexity

### 2.1 Measurements
- About 33 700 lines of Dart in `lib/` (app 17 600, core 4 700, http 3 400, import 2 900, storage 2 200, runner 1 100, script 1 100, cli 700) and 19 500 lines of tests. Test to code is healthy (app 0.6, http 0.8).
- The ratchet in `scripts/complexity_report.py --check` passes at 260 lines and 90 branches per function. It is too loose to guide work, and it counts the generated `prelude.dart` (a JavaScript runtime inside a Dart string, 251 lines, 88 branches) as the most complex function. The prelude should be excluded.
- Functions over 60 lines: 37; over 80 lines: 12; over 100 lines: 5 (excluding the prelude). Widget `build` methods over 60 lines: 15.
- Largest classes (lines, methods): `_ResultTableViewState` 1152 / 69, `_ResponseViewState` 937 / 48, `WorkspaceRepository` 769 / 82, `_CollectionsSidebarState` 514 / 29, `_AdaptiveScaffoldState` 502 / 34, `EditorNotifier` 455 / 18, `_RunnerPageState` 411 / 19, `_Connection` 358 / 32.
- Largest files: `result_table_view.dart` 1215, `response_view.dart` 1111, `result_table.dart` 805, `request_editor.dart` 794, `workspace_repository.dart` 787, `engine.dart` 713, `postman.dart` 689, `cli.dart` 668, `adaptive_scaffold.dart` 659, `realtime.dart` 646.
- Branchiest functions are parsers and scanners (`graphql/completion.dart _scan` 35, `js_syntax.dart tokenizeJs` 35, `cookie_jar.dart _parse` 32, `graphql/lexer.dart` 32, `graphql/schema.dart _definition` 30, `curl.dart _consume` 25). These are inherently branchy; the aim is clarity (small named states), not a lower number at any price.
- Static analysis is only `flutter_lints` defaults: no `strict-casts`, `strict-raw-types` or `strict-inference`.

### 2.2 Where the complexity hurts
1. **God state classes in the UI.** `_ResultTableViewState` mixes selection, keyboard, pointer, clipboard, sorting, column sizing, menus and layout; `_ResponseViewState` mixes mode switching, search, filtering, the table source and toolbars. Both are covered by many tests but are hard to change safely (the 0.64.x table work needed several rounds).
2. **`WorkspaceRepository` does everything** for nodes, environments, variables, examples, revisions, attachments and metadata in one 82-method class.
3. **`_Connection` in the HTTP engine** combines connecting, TLS setup, writing, reading, chunked and length framing, and timeouts.
4. **`cli.dart` and `postman.dart`** are single files holding many commands or both directions of an import/export format.
5. **Deep widget trees**: `build` methods at nesting depth 12 to 18 (`request_editor`, `command_palette`, `url_bar`).

## 3. Plan

Principles: every step is behaviour-preserving, ships with the tests that already exist plus characterisation tests where coverage is thin, keeps all goldens and the no-motion audit green, and is one pull request (a `chore` or `minor` in the release workflow). Security fixes (S1 to S5) go first because they are small and user-visible. Refactors go by risk: pure packages first, then state, then widgets.

### Phase A: quick security fixes (0.65.x patch releases)
Status 2026-10-21: A1, A2, A3, A4, A6 done (0.65.1); A5 deferred (needs a device check); S8 mitigated by `pdfrx` 2.9.0. S4 (response size cap) and S9 are not done yet.
- A1 (S1): Android backup off, extraction rules, manifest test. Release note.
- A2 (S5): `permissions: contents: read` in `ci.yml`; org default to read-only.
- A3 (S3): CLI refuses scripts without the Node permission model unless forced; tests.
- A4 (S2): history defaults and retention; Settings text; tests on defaults and clearing.
- A5 (S7): verify and remove `usesCleartextTraffic`.
- A6 (S6): scheduled OSV/`cargo audit` workflow.

### Phase B: measurement and guardrails
Status 2026-10-21: done. `complexity_report.py --check` now limits functions to 100 lines and 50 branches, classes to 800 lines and files to 1000 lines, skips the generated prelude, and keeps the known debt (9 items) in `scripts/complexity_allowlist.txt`. `strict-casts`, `strict-raw-types`, `strict-inference`, `unawaited_futures` and `avoid_dynamic_calls` are on in every package (`avoid_dynamic_calls` is off only in the http and import tests). Lower the limits as phases C to E shrink the allowlist.
- B1: exclude `prelude.dart` from `complexity_report.py`; add class and file size to the report; make the report print the top offenders in CI.
- B2: lower the ratchet in steps: functions 260/90 to 150/60 now, then 100/45, then 80/40; classes 600; files 800. Keep a short, dated allowlist file for the known offenders so the gate can be strict for new code.
- B3: turn on `strict-casts`, then `strict-raw-types`, then `strict-inference`, one package at a time (`core`, `http`, `storage`, `import`, then the app), fixing what each flags. Add `avoid_dynamic_calls` and `unawaited_futures`.

### Phase C: pure packages (lowest risk, best tests)
Status 2026-10-21: C1 started: `RevisionStore`, `EnvironmentStore` (variables and environments) and `ExampleStore` are separate classes in `packages/verbnest_storage`, with `WorkspaceRepository` delegating (769 to 603 lines, public API unchanged, all tests unchanged). Left for C1: nodes and tree, containers, requests, snapshot support. C2 done: `redirects.dart`, `request_writer.dart` and `response_reader.dart` are split out of `engine.dart` (713 to 423 lines), with redirect rule tests. C3 done for the `run` command (`_run` 204 lines to small steps); other commands are under the limit. The 167-line headless request step is a small class (`_StepRun`). C4 and C5 not started.
- C1 (`WorkspaceRepository`): split into `NodeRepository`, `EnvironmentRepository`, `ExampleRepository`, `RevisionRepository`, `AttachmentRepository` behind the same public facade, so callers do not change; move SQL to one file per aggregate. Target: no class over 300 lines.
- C2 (`engine.dart`): extract `ConnectionSetup` (DNS, proxy, TLS), `RequestWriter` and `ResponseReader` from `_Connection`; keep `HttpEngine` public API unchanged. Existing engine, HTTP/2 and proxy tests are the net.
- C3 (`cli.dart`): one file per command (`run`, `send`, `import`, `export`, `history`, `vault`) with a small shared option layer; keep exit codes.
- C4 (`postman.dart`, `openapi.dart`, `snapshot.dart`): split reading from writing per format; share a `JsonReader` with typed accessors (S10).
- C5 (`cookie_jar.dart`, `curl.dart`, `graphql/*`): turn the long `_parse`/`_consume`/`_scan` functions into small step methods or a state table; add table-driven tests first so behaviour is pinned.

### Phase D: app state
- D1 (`EditorNotifier`, 455 lines): separate sending (prepare, send, record) from editing and from script flow; one provider per concern.
- D2 (`_AdaptiveScaffoldState`, `_CollectionsSidebarState`, `_RunnerPageState`): move actions (drag and drop, rename, run) into plain controller classes with their own unit tests; keep widgets for layout.

### Phase E: widgets (highest risk; goldens and the audit are the safety net)
Status 2026-10-21: E1 started: `TableSelection` and `TableColumnSizer` are their own classes with unit tests, and the table header is split into label, resize handle and corner; `_ResultTableViewState` is 1054 lines (was 1152), still over the 800 limit and on the allowlist. E2 and the rest of E3 not started.
- E1 (`ResultTableView`): extract a `TableSelectionController` (selection model and keyboard), a `TableClipboard` (copy and export strings), `TableColumnLayout` (widths, fit, resize), and a menu builder; the State keeps only layout and gesture wiring. Target: no file over 600 lines, State under 400.
- E2 (`ResponseView`): extract `BodyToolbar`, `TableSourceBar` and `ResponseFilter` widgets and a `ResponseViewController` for mode, search and filter.
- E3 (`request_editor`, `status_bar`, `command_palette`, `url_bar`, `graphql_editor`): break `build` methods over 60 lines into named private widgets; no behaviour change.
- Each E step: run the goldens, `no_motion_audit_test`, `body_view_frames_test` (macOS), and the device matrix tests before merging.

### Phase F: verification
Status 2026-10-21: F1 done for the core and http parsers (fuzz tests in `packages/verbnest_core/test/fuzz_test.dart` and `packages/verbnest_http/test/fuzz_test.dart`; the importers already had one). The first long run found a real bug (quoted JSONPath keys), now fixed. Fuzzing the HTTP/2 and WebSocket frame parsers, and F2 (threat model), are not done.
- F1 (S10): fuzz or property tests for the importers (Postman, OpenAPI, HAR, cURL, snapshots), the cookie parser, the HTTP/2 and WebSocket framing, and JSONPath, run in CI with a time budget.
- F2: a short threat model in `docs/spec/` (assets, trust boundaries, abuse cases) and an external review before 1.0.

### Targets when done
- No function over 80 lines (`build` over 60), none over 40 branches, no class over 400 lines, no file over 600 lines, except generated code and listed parsers.
- `strict-casts`, `strict-raw-types`, `strict-inference` on in every package.
- All findings S1 to S7 closed; S8 to S10 tracked.
- Test count and coverage not lower than today; goldens unchanged except where a step says otherwise.

### Order and cost (rough, for one maintainer)
A: 2 to 3 days. B: 1 to 2 days. C: 6 to 8 days. D: 3 to 4 days. E: 6 to 8 days. F: 3 to 5 days. Do A and B first; C to F can be interleaved with feature work, one phase per release.

### Rollback
Each step is its own pull request and release tag, so a regression is reverted by reverting that pull request. Security steps A1 and A3 change user-visible behaviour; they get changelog lines.
