# Open Questions

Each question has a recommended default that the kit already assumes. Change any of them by editing this file and the affected documents.

| # | Question | Recommended default | Why |
|---|---|---|---|
| 1 | Licence | **Apache-2.0** | Permissive, patent grant, friendly to corporate contributors. MIT is the simpler alternative; GPL/AGPL would deter company adoption. |
| 2 | Workspace storage: files vs. SQLite | **SQLite, one `.verbnest` file per workspace** (ADR-007) | Uniform on all five platforms, transactional, fast at scale. Git workflows covered by YAML snapshot export/import; revisions replace git history. |
| 3 | Script engine | **QuickJS-ng via FFI** | Same engine on all platforms, iOS-safe; validated in Phase 0 spike. |
| 4 | Support Flutter web? | **No** (Constitution-level, ADR-005) | CORS and forbidden headers make it misleading. Could revisit with a desktop/CLI "agent" that the web UI drives. |
| 5 | Sync model | **Explicit exchange: `.verbnest` files and YAML snapshots; no hosted service** | Matches local-first principle. Live sync of a SQLite file is unsafe, so any future sync needs a row-level protocol (self-hosted, opt-in) and a constitution check. |
| 6 | Minimum Android version | **API 24 (7.0)** | ~97 % device coverage; Flutter supports it. |
| 7 | In-app git | **Dropped; use YAML snapshots with external git** | The database is not a git working tree. Revisit if snapshot workflows prove too clumsy. |
| 13 | Team collaboration without git | **Snapshot exchange now; evaluate row-level sync later** | Needs an ADR and constitution check before any server component. |
| 8 | Name and trademark check for "Verbnest" | **Run a trademark search (classes 9 and 42) before public launch** | The name replaced "PostIt" in v0.43.0 because "Post-it" is a 3M trademark. Availability on npm, pub.dev, GitHub and common domains was checked, not trademarks. |
| 9 | Telemetry | **None** | Constitution I. Crash reports only if user explicitly opts in (e.g. Sentry self-hosted). |
| 10 | Monetisation / sustainability | **Donations + sponsorship (GitHub Sponsors, Open Collective)** | Keeps product free; optional paid hosted add-ons would need a constitution amendment. |
| 11 | State management | **Riverpod 3 + freezed** | Testable, no BuildContext coupling, strong community; Bloc is an acceptable alternative if maintainers prefer. |
| 12 | Editor component | **re_editor** | Proven on large text in a shipping Flutter API client; validate in Phase 0. |
