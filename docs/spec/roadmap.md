# Roadmap

Phases are scoped by outcome, not by calendar. Each has exit criteria that must be met on **all five platforms** unless a limitation is documented.

## Phase 0: Foundations
Goal: a repo where contributors can build, test and ship an empty-but-real app on every platform.

- Monorepo with pub workspaces + melos; package skeletons from architecture.md.
- CI: analyze, test, build all five targets on every PR.
- `test_server/` with HTTP/1.1 echo, TLS listeners, redirects, delays.
- ADR-001 … ADR-005 and ADR-007 written (ADR-002 proposed until its spike runs; ADR-007 proposed).
- Storage spike (e): drift + bundled SQLite with FTS5 and WAL on all five platforms; 10,000-request workspace open/search timings; crash-injection test.
- App shell: `AdaptiveScaffold` with compact/medium/expanded layouts, theme, settings stub.
- Spike reports: (a) custom HTTP engine timing accuracy vs. curl; (b) QuickJS-ng FFI build on all five platforms incl. iOS; (c) re_editor with 5 MB JSON on a low-end Android device; (d) secure storage on Linux without a keyring.

**Exit:** signed debug builds launch on Android, iOS, macOS, Windows, Linux; spikes have go/no-go decisions recorded.

## Phase 1: MVP ("send, save, switch")
Goal: a developer can replace Postman for everyday REST work, offline, on any device.

- HTTP engine (HTTP/1.1, TLS, redirects, cancel, compression, auto headers, raw view).
- Request editor: method, URL with vars, params, path vars, headers, all body modes, settings.
- Response viewer: status/time/size, pretty/raw/preview (images), headers, cookies (read-only), search, save/share, large-body streaming.
- Workspace SQLite database v1 (ADR-007) with drift migrations, local database, collections/folders, drag & drop, search (FTS5), `.postit` import/export.
- Environments, globals, collection variables, secrets in OS store, dynamic vars (core set), quick-look.
- Auth: inherit, none, API key, bearer, basic, OAuth2 client credentials & password.
- History with restore/save.
- Import: cURL, Postman v2.0/v2.1 collections, environments, globals. Export: Postman v2.1, cURL.
- Keyboard shortcuts, light/dark, autosave drafts.
- Distribution: GitHub Releases for all desktops + Android APK; TestFlight; Flathub submission started.

**Exit:** FR-*-P0 complete; Postman corpus round-trips; NFR-PERF-001/002 met; 10 external beta testers across all platforms complete the "import my Postman collection and use it for a day" script.

## Phase 2: v1.0 ("test and automate")
Goal: parity with Postman's core testing workflow.

- Scripting: QuickJS-ng runtime, pre/post scripts at all levels, `pm` API, chai, bundled libs, console, Tests tab, snippets.
- No-code assertions.
- Collection runner with data files, flow control, reports (JUnit/JSON/HTML).
- Auth: OAuth2 auth code/PKCE/implicit + token manager, Digest, JWT, AWS SigV4; client certs; custom CA.
- Cookies manager, proxy settings, HTTP/2, timing breakdown & TLS info.
- Import OpenAPI/Swagger, HAR, Postman data dump; code generation (all listed languages).
- Saved examples; favourites; command palette; localisation framework.
- YAML snapshot export/import (FR-WS-006) and per-request revision history (FR-WS-008).
- Store releases: Google Play, F-Droid, App Store (iOS + macOS), Microsoft Store/winget, Flathub.

**Exit:** `pm` conformance corpus ≥ 95 % passing; runner reports validated by CI tools (JUnit schema); store approvals obtained; v1.0 tagged.

## Phase 3: v1.x ("real-time")
Goal: cover the modern API surface beyond REST.

- GraphQL: editor, variables, introspection, schema explorer, autocomplete, SDL import.
- WebSocket client with saved messages and message log.
- SSE viewer.
- Mobile background/resume handling for live connections.
- Response JSONPath/XPath filter, HTML/PDF preview, hex view.

**Exit:** FR-GQL-001..003, FR-RT-001/002/004 complete with integration tests on all platforms.

## Phase 4: v2.0 ("every RPC")
Goal: make PostIt the best open source tool for remote function call testing.

- 4a: gRPC via reflection and descriptor sets (all call types, metadata, TLS), dynamic protobuf codec.
- 4b: pure-Dart `.proto` parser; gRPC-Web.
- Socket.IO, MQTT, JSON-RPC 2.0, XML-RPC, SOAP (+ WSDL import).
- MCP client spike → feature if validated (tools/resources/prompts over Streamable HTTP; stdio on desktop).
- GraphQL subscriptions.

**Exit:** FR-RPC-001..006 complete; gRPC dynamic codec byte-identical with protoc goldens across the corpus.

## Phase 5: Platform & ecosystem
- Headless CLI (`postit run`, `postit mock`) as native binaries for Linux/macOS/Windows; GitHub Action and GitLab CI templates.
- Local mock server from examples.
- OpenAPI contract validation of responses; static docs export.
- Performance mode in runner (desktop).
- Plugin API (auth providers, importers, visualisers); `pm.visualizer`.
- External secret providers (HashiCorp Vault, 1Password CLI, AWS Secrets Manager).
- Optional self-hostable sync server (only if file/snapshot exchange proves insufficient; requires constitution check).
- Postbot-like assistant with bring-your-own LLM key (opt-in).

## Release workflow: commit per phase, bump by change type

Work is committed once per finished phase (or phase step), never mid-step. Each commit carries a change type that decides the version bump. One version covers the whole workspace and is stored in `VERSION`; `scripts/bump_version.sh` copies it into every `pubspec.yaml`.

| Type | Bump | Example |
|---|---|---|
| `feature` | major (0.1.0 → 1.0.0) | A finished roadmap phase or a new user-facing capability |
| `minor` | minor (0.1.0 → 0.2.0) | A smaller addition to an existing capability |
| `fix` | patch (0.1.0 → 0.1.1) | A bug fix |
| `chore` | none | Docs, refactors, tests, CI, tooling, dependency updates |

Rules:
1. A phase step is committed only when analyze and tests are green on the packages it touches.
2. The build number increases after every build and never decreases. It lives in `BUILD_NUMBER`, is mirrored as the `+N` in `apps/postit_app/pubspec.yaml`, and is passed to Flutter as `--build-number`. All builds (local, CI, release) go through `scripts/build.sh`, which increments it first; a failed build still uses up its number. A version bump never resets it, because the stores require build numbers to rise across versions.
3. Commit message: `<type>(<scope>): <summary> (v<version>)`; `chore` uses `(build <N>)` instead because its version does not change.
4. `feature`, `minor` and `fix` commits update `CHANGELOG.md` and get an annotated tag `v<version>`; `chore` gets neither.
5. Pushing and publishing releases stay manual.
6. `.claude/context.md` is updated twice per phase step: before work starts (goal, FR IDs, ⏳/✅ checklist, planned version) and on completion (result, what was left out, what is untested). The completion update is part of the phase commit.
7. Release build (macOS): after the phase commit, `scripts/package_macos.sh` builds `flutter build macos --release` through `scripts/build.sh` (which raises the build number), ad-hoc signs `PostIt.app`, packages a styled DMG with `create-dmg` (plain `hdiutil` fallback) and moves it to `~/Downloads` as `PostIt-<version>+<build>-macos-<arch>.dmg`. The build number change is committed afterwards as a `chore`. Notarisation needs a Developer ID and stays manual.
8. Claude Code runs this with `/phase-commit <type> <summary>` (see `.claude/commands/phase-commit.md`).

Because `feature` bumps major, the first `feature` commit moves the project to 1.0.0. Treat that as the MVP release (end of Phase 1); use `minor` for steps before it.

## Milestone tracking
- Each phase becomes a GitHub milestone; each FR becomes an issue labelled with its ID and priority.
- Phase demos recorded on one phone, one tablet and one desktop.
- Release cadence after v1.0: minor every 6 weeks, patch as needed; LTS not planned before v2.

## Top risks and mitigations

| Risk | Impact | Mitigation |
|---|---|---|
| Custom HTTP engine edge cases (chunked, HTTP/2 flow control, proxies) | Wrong results erode trust | Large integration suite vs. test server; native adapter as escape hatch; differential testing vs. curl |
| QuickJS FFI build complexity on 5 platforms (esp. iOS, Windows arm64) | Scripting slips | Phase 0 spike; fallback to `flutter_js` short-term |
| Postman script compatibility gaps | Migration friction | Conformance corpus; clear "unsupported API" errors; prioritise by usage |
| Linux webview & keyring fragmentation | Degraded Linux UX | Fallbacks (open in browser, encrypted file store); Flatpak as reference distro |
| App Store review (interpreter, arbitrary loads) | iOS/macOS store delays | Precise review notes; direct-download macOS build; TestFlight for early users |
| Mobile background limits | Long runs/streams interrupted | Document; foreground service on Android; resume UX |
| Scope creep toward Postman's cloud features | Never shipping | Constitution I/II; out-of-scope list in feature inventory |
