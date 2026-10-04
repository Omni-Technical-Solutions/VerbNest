# ADR-007: Store workspace data in SQLite instead of files

- **Status:** Accepted by the maintainer on 2026-10-04 (constitution amendment rule satisfied)
- **Supersedes:** ADR-003 (YAML one-request-per-file workspace format)
- **Amends:** Constitution II (and wording in I.2)
- **Affects:** FR-WS-001..006, FR-VAR-002, FR-VAR-007, FR-COL-003, FR-IO-003, NFR-REL-001, NFR-PERF-004, FR-HIS-*, testing.md §3 (Storage row), roadmap Phase 1

## Context
The original kit stored workspaces as a YAML tree so they could live in git. That costs a lot on the platforms PostIt targets: phones and tablets have no good folder access (SAF, security-scoped bookmarks, sandboxed Flatpak), file watching is unreliable off-desktop, crash safety needs hand-built atomic writes, and a 10,000-request workspace means 10,000 files to scan on every launch.

## Decision
1. A workspace is **one SQLite file** (`<name>.postit`) accessed through drift. It holds collections, folders, requests, examples, environments and variables (initial values), workspace settings and per-request revision history.
2. Device-local data stays in a separate **local database** in app support storage, keyed by workspace id: history, runs, current variable values, cookies, OAuth token metadata, UI tabs and the FTS5 index. It is never exported with the workspace, so sharing a workspace cannot leak history or current values.
3. Secrets stay in the OS secret store.
4. Git-friendliness is kept as an **export/import feature**, not the storage layer: "Export YAML snapshot" writes the former file layout; "Import snapshot" reads it back. Round trip must be lossless.
5. A `.postit` file is the unit of sharing and backup (copy it, attach it, or put it in any file-sync folder while PostIt is closed).

## Consequences
**Good**
- Same storage path on all five platforms; no folder permissions for the default case.
- Transactions give crash safety for free; search and tree queries are indexed; opening a huge workspace is fast.
- No file watcher, no external-edit conflict handling, no `*.local.yaml` mechanism.

**Bad / costs**
- Binary file: no line-level `git diff`/merge, no editing in a text editor. Mitigated by the YAML snapshot export and a built-in per-request revision history.
- Team collaboration via git pull/merge is now an explicit snapshot workflow rather than the default.
- Opening a live database inside a cloud-synced folder can corrupt it (WAL sidecar files). PostIt opens workspaces in WAL mode, warns when a path looks like a synced folder, and recommends export/import for sharing.
- Two processes must not write the same file: the app takes an exclusive lock and the future CLI opens read-only or on a copy.

## Alternatives considered
- Keep YAML files (previous decision): best for git, worst for mobile and scale.
- Hybrid with files as source and SQLite as cache: needs both sync directions and conflict handling; rejected as the most complex option.

## Follow-ups
- Replace `postit_storage` YAML work with a drift schema and migrations (data-model.md §1-4).
- Reword feature-inventory and roadmap items that relied on git as the sync model.
