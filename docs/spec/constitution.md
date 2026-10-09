# VerbNest Constitution

These principles outrank every other document in the kit. When a feature request, PR or design conflicts with one of them, the principle wins unless the constitution itself is amended (see the end of this file).

## I. Local-first, account-free
1. VerbNest MUST be fully usable offline with no account, no login and no telemetry by default.
2. All user data (collections, environments, history) lives on the user's device. Any sharing or sync is opt-in and pluggable (workspace file/bundle exchange, YAML snapshots in git, or self-hosted), never a vendor cloud requirement.
3. Telemetry, if ever added, is opt-in, anonymous, documented field by field, and off by default.

## II. SQLite is the source of truth, and users can always take their data out
*(Amended by ADR-007; previously "plain files are the source of truth".)*
1. Workspace content (collections, folders, requests, examples, environments, variables, settings) is stored in a **workspace database**: one self-contained SQLite file per workspace. Device-local state (history, run results, current variable values, cookies, UI state, search index) is stored in a separate **local database** that is never part of the workspace.
2. Every write is a transaction; a crash or power loss MUST NOT corrupt or half-apply a change. The schema is versioned and migrated forward only with tested migrations.
3. The workspace database is a documented, stable format (schema published in data-model.md). Users MUST be able to leave: a workspace can be exported at any time to a copy of the `.verbnest` file, to Postman v2.1, and to a human-readable YAML folder snapshot (see FR-WS-006), and a snapshot can be imported back without loss.
4. Secrets are never written into either database or any export. They live in the OS secure store and are referenced by name.

## III. One codebase, five first-class platforms
1. Android, iOS, Linux, macOS and Windows are all first class. A feature is "done" only when it works on all five, or when the platform limitation is documented in the feature's spec and surfaced in the UI.
2. Platform-specific code is isolated behind interfaces in a `platform/` layer. Business logic never imports `dart:io` directly where an abstraction exists.
3. The UI adapts to form factor (phone, tablet, desktop) rather than shipping a shrunken desktop UI to phones.

## IV. Protocol core is UI-independent
1. Request execution, variable resolution, scripting, import/export and the collection runner live in pure Dart packages with no Flutter dependency.
2. That core MUST be usable from a headless CLI (`verbnest run`) so CI pipelines get the same behaviour as the app.

## V. Fidelity over convenience
1. What the user sees is what was sent. The app MUST show the exact final request (resolved URL, headers incl. auto-added ones, body bytes) and the raw response, including timing and TLS details where the platform allows.
2. VerbNest never silently rewrites user input (header casing, URL encoding, body formatting) unless the user opted in.

## VI. Interoperability, not lock-in
1. Import from Postman (v2.0/v2.1 collections, environments, globals, data dumps), Insomnia, Bruno, OpenAPI 3.x/Swagger 2.0, HAR, cURL.
2. Export to Postman v2.1, OpenAPI (best effort), HAR and cURL. Users can always leave.
3. Scripting uses a `pm`-compatible API so most existing Postman scripts run unmodified.

## VII. Secure by default
1. TLS verification is on by default; turning it off is per-request or per-environment and visibly flagged.
2. Scripts run in a sandbox with no file-system or network access beyond the documented `pm.sendRequest` and explicitly granted capabilities.
3. Secret variables are masked in UI, logs, history and exports unless explicitly revealed.

## VIII. Fast and accessible
1. Cold start under 2 s on a mid-range device; typing in editors never drops frames on large (5 MB) bodies thanks to virtualised rendering.
2. All features reachable by keyboard on desktop and by screen reader on all platforms (WCAG 2.2 AA target).

## IX. Open source, open governance
1. Licence: Apache-2.0 (recommended; see open-questions.md). Contributions under DCO.
2. Specs, ADRs and roadmap live in the repo. Significant changes require an ADR in `docs/adr/`.

## X. Test-first core
1. Every FR in the core packages has automated tests before it is marked done.
2. Every protocol is tested against a local, reproducible test server (see testing.md); no test depends on a third-party public endpoint.

## Amending the constitution
An amendment needs an ADR, a PR labelled `constitution`, and approval from a majority of maintainers. The amendment's ADR lists every existing FR it affects.
