# ADR-015: Rename PostIt to Verbnest

Status: accepted (v0.43.0)

## Context

"Post-it" is 3M's registered trademark and every search for it returns sticky
notes. A product needs a name it can own. Candidates were checked for
availability on npm, pub.dev, GitHub and the .com/.dev/.app/.io domains.

## Decision

- The product is **Verbnest**: "verb" for HTTP verbs, "nest" for the local
  home of a workspace.
- Everything visible changes: packages, CLI (`verbnest`, short `vn`), file
  extension (`.verbnest`), bundle id (`com.omni.verbnest`), env vars, headers,
  docs, CI, repo name.
- Old data and habits keep working through read-only compatibility: `.postit`
  files, `postit.yaml` snapshots, `POSTIT_*` variables, `X-PostIt-*` headers,
  the `postit.secrets.<id>` vault key (moved on first load), and the old
  app-data folder (copied once, left in place).
- Kept as they were: the SQLite `application_id`, the keychain service name,
  and the history in CHANGELOG.md.

## Consequences

- A new bundle id means stores see a new app and macOS asks once for keychain
  access. Android needs a new Play listing under `com.omni.verbnest`.
- The `postit` command is gone; scripts must call `verbnest` or `vn`.
- A trademark search for "Verbnest" is still required before public launch
  (open question 8).
