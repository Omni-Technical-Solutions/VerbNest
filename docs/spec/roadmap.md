# Roadmap

Phases are scoped by outcome, not by calendar. Each has exit criteria that must be met on **all five platforms** unless a limitation is documented.

## Phase 0: Foundations
Goal: a repo where contributors can build, test and ship an empty-but-real app on every platform.

- Monorepo with pub workspaces + melos; package skeletons from architecture.md.
- CI: analyze, test, build all five targets on every PR.
- `test_server/` with HTTP/1.1 echo, TLS listeners, redirects, delays.
- ADR-001 … ADR-005 written and accepted.
- App shell: `AdaptiveScaffold` with compact/medium/expanded layouts, theme, settings stub.
- Spike reports: (a) custom HTTP engine timing accuracy vs. curl; (b) QuickJS-ng FFI build on all five platforms incl. iOS; (c) re_editor with 5 MB JSON on a low-end Android device; (d) secure storage on Linux without a keyring.

**Exit:** signed debug builds launch on Android, iOS, macOS, Windows, Linux; spikes have go/no-go decisions recorded.

## Phase 1: MVP ("send, save, switch")
Goal: a developer can replace Postman for everyday REST work, offline, on any device.

- HTTP engine (HTTP/1.1, TLS, redirects, cancel, compression, auto headers, raw view).
- Request editor: method, URL with vars, params, path vars, headers, all body modes, settings.
- Response viewer: status/time/size, pretty/raw/preview (images), headers, cookies (read-only), search, save/share, large-body streaming.
- Workspace file format v1, collections/folders, drag & drop, search (FTS5).
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
- Git panel on desktop (status, commit, pull, push).
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
- Optional self-hostable sync server (only if git sync proves insufficient; requires constitution check).
- Postbot-like assistant with bring-your-own LLM key (opt-in).

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
