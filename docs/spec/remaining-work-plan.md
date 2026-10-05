# Remaining work, in phases

Status at v0.31.0. Each phase is one release: its own commit, version bump
(feature = major, change = minor, fix = patch), CHANGELOG entry, context
update and tests. Analyze and all tests must pass before each commit.

## Phase 1: UI strings to ARB (minor)

Finding: `context.l10n` already falls back to English when a test pumps a bare
`MaterialApp`, so existing widget tests keep passing. The earlier blocker
does not exist.

- 1a. Add a guard test that lists hard-coded `Text('...')` literals per file
  and fails when a migrated file regains one (allow-list for the rest).
- 1b. Migrate new screens first (realtime dialog, mock dialog, graphql editor,
  timing dialog, runner page), then sidebar, request editor, response view,
  settings, environments, history, import/export dialogs.
- 1c. For each batch: add keys to `app_en.arb` and `app_ar.arb` (Arabic
  written with the English meaning kept; flag for native review), run
  `flutter gen-l10n`, replace literals, run tests.
- Done when the allow-list is empty or holds only technical literals (method
  names, `{{var}}` syntax, file extensions).
- Risk: placeholders and plurals. Mitigate with ICU messages and a test that
  every key exists in both ARB files.

## Phase 2: Windows and Linux verification (patch)

Needs the CI to run, which needs a remote.

- 2a. Add a remote and push (user action). Read the first CI run; fix
  path, line-ending and TLS-certificate-generation failures (`openssl` is
  absent on Windows runners; the test server's certificate helper needs a
  fallback or those tests need a skip with a reason).
- 2b. Add `flutter build windows` and `flutter build linux` to CI.
- 2c. Record results in `docs/release` and the roadmap.

## Phase 3: HTML and PDF preview (minor) - HTML done in v0.33.0, PDF open, see ADR-011

- 3a. ADR: HTML preview through `webview_flutter` or `flutter_inappwebview`
  with JavaScript off, no network (CSP `default-src 'none'`), and no
  navigation; PDF through `pdfrx` or `printing`. Pick by platform support
  matrix (macOS, Windows, Linux, iOS, Android).
- 3b. Response view segment "Preview" for `text/html`, and PDF for
  `application/pdf`; size cap (10 MB) with a message above it.
- 3c. Widget tests with a fake preview builder; manual checks per platform.

## Phase 4: Scripts in the CLI (minor) - done in v0.32.0, see ADR-010

- 4a. Spike (1 day): can the QuickJS library behind `fjs` load in a plain Dart
  process through `dart:ffi`? If yes, a `postit_script` package wraps it for
  both the app and the CLI. If no, evaluate `quickjs` FFI bindings or run the
  CLI through `flutter_tester`-free `dart compile exe` with a bundled
  `libquickjs`.
- 4b. ADR with the outcome. Move `script_engine`, `script_io`, `script_flow`
  and `prelude.dart` from the app into `postit_script` behind the existing
  `ScriptEngine` interface (the interface is already Flutter-free except the
  Riverpod provider).
- 4c. `HeadlessSender` runs pre and post phases like `EditorNotifier.send`
  (variables set by scripts are kept for the run; `setNextRequest` flows into
  `RunFlow`).
- 4d. Tests with a fake engine in unit tests plus one real-engine smoke test
  gated on library availability.

## Phase 5: Smaller follow-ups (patch each)

- Secrets for the CLI: read from the OS secret store through the same
  `SecretVault` the app uses, behind a `--secrets` flag.
- CLI history: optional `--record` to write runs into the local store.
- Mock server: query matching, `X-PostIt-Delay`, body matching.
- Live connections: saving messages with the request, binary send,
  SSE `Last-Event-ID` reconnect.
- GraphQL: GET transport, persisted queries, script-aware introspection.
- Scripting gaps: `pm.sendRequest`, `pm.cookies`, snippets.

## Order and dependencies

1 and 4 are independent and can go first. 2 waits for a remote. 3 needs the
ADR. 5 items are picked by need.

## Phase 5 status

- Done: mock query/body matching and delay (v0.34.0), SSE reconnect (v0.35.0), saving the live log (v0.36.0).
- Not planned: CLI history (it lives in the app's per-device store, which the CLI should not write) and CLI vault secrets (the vault is the OS keychain; the CLI uses `--var`).
- Open: binary send, GraphQL GET/persisted queries, `pm.sendRequest`/`pm.cookies`, PDF preview.
