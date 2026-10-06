# Testing Plan

## 1. Strategy (test pyramid)

| Layer | Scope | Tooling | Runs on |
|---|---|---|---|
| Unit | Pure Dart packages: resolver, parsers, signers, codecs, importers | `package:test`, `checks`/`matcher` | Every PR, Linux runner |
| Protocol integration | Engine vs. local test server (HTTP/1.1, HTTP/2, TLS, proxy, WS, SSE, gRPC, MQTT) | `package:test` + `test_server/` | Every PR: Linux, macOS, Windows runners |
| Script compatibility | `pm` API conformance corpus | `verbnest_script` tests on QuickJS | Every PR, all desktop runners |
| Golden / widget | Widgets and adaptive layouts at compact/medium/expanded | `flutter_test`, `alchemist` goldens | Every PR (Linux, pinned fonts) |
| App integration (E2E) | Real app flows on devices | `integration_test` + `patrol` (native dialogs, permissions) | Nightly + release: Android emulator, iOS simulator, macOS, Windows, Linux |
| Compatibility corpus | Postman import/export round-trip | CLI-driven corpus tests | Every PR |
| Performance | Startup, large bodies, big workspaces | `integration_test` with timeline summaries, `benchmark_harness` | Nightly, tracked over time |
| Security | Script sandbox escape, path traversal in import, secret leakage | Fuzzing (`package:test` + random corpora), static scans (OSV, Semgrep) | Nightly + release |
| Manual exploratory | Platform feel, accessibility, store compliance | Checklists below | Every release candidate |

Coverage targets: ≥ 90 % lines in `verbnest_core`, `verbnest_http`, `verbnest_io`, `verbnest_script`; ≥ 70 % app application layer; goldens for every screen in all three layout classes, light + dark.

## 2. Local test server (`test_server/`)

A Dart program started by tests (and runnable by contributors) exposing, on random ports:
- `/echo` returns method, path, query, headers (exact casing/order as received), body bytes as JSON.
- `/status/:code`, `/delay/:ms`, `/redirect/:n`, `/redirect-cross-origin`, `/gzip`, `/brotli`, `/chunked`, `/large/:mb`, `/stream/sse`, `/cookies/set`, `/basic-auth`, `/digest-auth`, `/bearer`, `/oauth2/*` (mini authorisation server incl. PKCE), `/aws-sigv4-verify`, `/hawk-verify`, `/upload` (multipart parse).
- TLS listener with self-signed CA, an expired cert, a wrong-host cert, and an mTLS listener requiring a client cert.
- HTTP/2 listener (ALPN h2) and h2c.
- HTTP CONNECT proxy and SOCKS5 proxy (with/without auth).
- WebSocket echo + server push; Socket.IO v4 server (Node sidecar in CI only, behind a flag); SSE emitter with `Last-Event-ID`.
- gRPC server with reflection, all four call types, metadata/trailers echo, deadlines.
- MQTT broker (embedded via `mosquitto` container in CI; skipped locally if absent).
- GraphQL endpoint with introspection and a subscription (`graphql-transport-ws`).

No test may hit the public internet (constitution X). A lint step greps tests for `http(s)://` hosts other than `localhost`/`127.0.0.1`/`[::1]`.

## 3. Test areas mapped to requirements

| Area | Key cases | FRs |
|---|---|---|
| Variable resolution | precedence across 5 scopes; recursion; cycles; disabled vars; secrets masked in history/export; dynamic vars once per occurrence | FR-VAR-001..006 |
| URL/params sync | encoding round-trip, duplicate keys, empty values, `?` in fragments, IDN hosts, IPv6 literals | FR-HTTP-002..004 |
| Wire fidelity | header order & casing preserved via `/echo`; custom methods; auto headers overridable; body bytes identical | FR-HTTP-005, 010 |
| Bodies | each mode incl. multipart with files, binary, large (100 MB) streamed upload | FR-HTTP-006 |
| Redirects & TLS | follow/don't, max count, auth stripped cross-origin, verify on/off, custom CA, mTLS PEM + PFX | FR-HTTP-007, 013 |
| Cancel/timeouts | cancel mid-upload/mid-download; connect vs. read timeout | FR-HTTP-009 |
| Proxy | HTTP CONNECT, SOCKS5, auth, bypass list | FR-HTTP-012 |
| Responses | large body streaming, truncated preview, charset detection, compressed sizes | FR-RES-* |
| Auth | every auth type against verifying endpoints; OAuth2 PKCE end-to-end (desktop loopback; mobile via patrol with Custom Tabs/ASWebAuthenticationSession) | FR-AUTH-* |
| Storage | transactions under simulated crash (kill during write, multi-row edits all-or-nothing); migrations from every released schema version via drift schema dumps; newer-schema and non-Verbnest files rejected untouched; exclusive-lock behaviour; unknown JSON keys preserved; local database deletion loses no workspace data; `.verbnest` export contains no history, current values or secrets | FR-WS-001..004, 007, 009, NFR-REL-001 |
| Snapshot | YAML snapshot export → import → export byte-identical; deterministic ordering; merge conflict list; path traversal and YAML alias bombs rejected | FR-WS-006 |
| Revisions | one revision per save, 50 cap, restore | FR-WS-008 |
| Import/export | corpus round-trip; malformed inputs; path traversal in file references; huge files | FR-IO-* |
| Scripting | `pm` conformance suite; sandbox (no `require('fs')`, no infinite loop past timeout, memory cap); `sendRequest` appears in console | FR-SCR-* |
| Runner | iterations × data rows; setNextRequest loops; stop-on-failure; JUnit output schema-valid | FR-RUN-* |
| Realtime | WS frames text/binary, close codes, reconnect; SSE reconnect with Last-Event-ID; background/resume on mobile | FR-RT-* |
| gRPC | reflection & descriptor set loading; all call types; dynamic codec round-trip vs. protoc-generated golden bytes | FR-RPC-001..004 |

## 4. Compatibility corpus
- `corpus/postman/`: ≥ 20 public Postman collections (licence-checked) covering every auth type, nested folders, scripts, examples, variables, form-data with files.
- Test: import → export v2.1 → semantic JSON diff (ignoring ordering of object keys and Postman-generated ids) must be empty.
- `corpus/scripts/`: Postman documentation snippets and common community test patterns; each has expected test results when run against the test server.
- `corpus/openapi/`: Petstore 2.0/3.0/3.1, Stripe and GitHub specs (large-file performance).
- `corpus/curl/`: 200 cURL commands (from docs of popular APIs) → parse → generate cURL → semantic equality.

## 5. Platform matrix

| Platform | CI unit/integration | E2E (patrol / integration_test) | Manual RC check |
|---|---|---|---|
| Android | Linux runner (Dart) | Emulator API 24, 30, 35 (x86_64); Firebase Test Lab or similar for 3 physical devices (nightly) | Pixel + Samsung, TalkBack |
| iOS/iPadOS | macOS runner | Simulator iOS 15, 18 (iPhone + iPad) | Physical iPhone + iPad, VoiceOver, local-network prompt |
| macOS | macOS runner (arm64) | Native app run | Sandbox (App Store) build + notarised DMG build; VoiceOver |
| Windows | Windows runner (x64) | Native app run | MSIX + installer; Narrator; firewall prompt behaviour; arm64 smoke |
| Linux | Ubuntu runner (x64), arm64 nightly | Native app run under Xvfb (X11) and weston (Wayland, nightly) | Flatpak build on GNOME + KDE; Orca smoke; no-keyring fallback |

## 6. Performance tests (NFR)
- Cold start time (`flutter run --profile --trace-startup`) per platform; fail if > target +10 %.
- Pretty-print + render of 5 MB JSON; scroll jank (frame build/raster time p90 < 16 ms).
- Workspace with 10,000 requests: open time, search latency, tree scroll.
- Engine overhead vs. `curl` on the `/echo` endpoint: 1,000 sequential requests, p95 delta < 5 ms.
- Memory with 20 open tabs and 10 large responses.

## 7. Security tests
- Script sandbox fuzzing: generated JS attempting prototype pollution of host bridge, infinite loops, deep recursion, giant allocations; must terminate cleanly within limits.
- Import hardening: zip-slip/path traversal in Bruno/Insomnia/data-dump archives; billion-laughs XML in SOAP/WSDL; YAML alias bombs.
- Secret leakage: grep the workspace and local databases (including WAL files), logs and exports after a scripted session using secrets; zero occurrences allowed.
- TLS: verify that disabling verification is scoped to the request/environment that set it.

## 8. CI pipeline (GitHub Actions)
1. `analyze`: `dart format --set-exit-if-changed`, `flutter analyze`, custom lints, licence check, no-public-hosts check.
2. `test-core`: unit + protocol integration on ubuntu/macos/windows.
3. `test-app`: widget + golden tests on ubuntu.
4. `build`: debug builds for all five targets (Android APK, iOS no-codesign, macOS, Windows, Linux) to catch platform compile breaks on every PR.
5. `e2e` (nightly + release branches): patrol suites on Android emulator and iOS simulator; integration_test on desktops.
6. `release`: signed artefacts, SBOM, checksums, store uploads (manual approval).

## 9. Definition of Done (per feature)
- FR acceptance criteria automated (unit/integration) and green on all CI platforms.
- Widget/golden tests for new UI in compact, medium and expanded layouts, light and dark.
- Manual smoke on one mobile and one desktop platform; platform limitations documented in the FR and in-app.
- Accessibility labels present; keyboard path on desktop.
- Docs page updated; changelog entry.
- Committed as one commit per phase step with a change type and version bump (roadmap.md, Release workflow).
