# Changelog

Versioning follows `docs/spec/roadmap.md` (Release workflow): feature = major, minor = minor, fix = patch, chore = no version change. The build number is separate and rises with every build (`BUILD_NUMBER`). One version covers the whole workspace.

## 0.2.0

- `postit_core` domain models: `KeyValue`, `Auth` (inherit, none, API key, bearer, basic, raw passthrough), `RequestBody` (raw languages, urlencoded, form, binary), `HttpRequestItem`, `RequestSettings`, `Scripts`, `Environment`.
- URL helpers for query params and `:path` variables that never decode or rewrite user text (FR-HTTP-003, FR-HTTP-004).
- Auth inheritance resolution (FR-COL-002). Unknown keys and auth types round-trip.

## 0.1.0

- Monorepo scaffold: `postit_core` (variable resolver), `postit_http` (HTTP/1.1 engine), `test_server`, `postit_app` (adaptive shell).
- Spec kit with SQLite workspace storage (ADR-007, proposed).
