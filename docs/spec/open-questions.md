# Open Questions

Each question has a recommended default that the kit already assumes. Change any of them by editing this file and the affected documents.

| # | Question | Recommended default | Why |
|---|---|---|---|
| 1 | Licence | **Apache-2.0** | Permissive, patent grant, friendly to corporate contributors. MIT is the simpler alternative; GPL/AGPL would deter company adoption. |
| 2 | Storage format: YAML vs. JSON vs. a custom DSL (Bruno's `.bru`) | **YAML, one request per file** | Readable, multi-line bodies/scripts diff cleanly, mature Dart libs; custom DSL adds parser burden. |
| 3 | Script engine | **QuickJS-ng via FFI** | Same engine on all platforms, iOS-safe; validated in Phase 0 spike. |
| 4 | Support Flutter web? | **No** (Constitution-level, ADR-005) | CORS and forbidden headers make it misleading. Could revisit with a desktop/CLI "agent" that the web UI drives. |
| 5 | Sync model | **Git first; no hosted service** | Matches local-first principle; self-hosted sync only if users demand it. |
| 6 | Minimum Android version | **API 24 (7.0)** | ~97 % device coverage; Flutter supports it. |
| 7 | Mobile git | **P2; folder sync (iCloud/SAF) meanwhile** | No mature pure-Dart git; libgit2 FFI is heavy on mobile. |
| 8 | Name and trademark check for "PostIt" | **Run a trademark search before public launch** | "Post-it" is a 3M trademark; a distinct spelling/brand (e.g. "PostIt API" or a new name) may be required. |
| 9 | Telemetry | **None** | Constitution I. Crash reports only if user explicitly opts in (e.g. Sentry self-hosted). |
| 10 | Monetisation / sustainability | **Donations + sponsorship (GitHub Sponsors, Open Collective)** | Keeps product free; optional paid hosted add-ons would need a constitution amendment. |
| 11 | State management | **Riverpod 3 + freezed** | Testable, no BuildContext coupling, strong community; Bloc is an acceptable alternative if maintainers prefer. |
| 12 | Editor component | **re_editor** | Proven on large text in a shipping Flutter API client; validate in Phase 0. |
