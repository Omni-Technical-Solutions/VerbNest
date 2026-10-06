# Rename plan: PostIt to Verbnest

Status: done (v0.43.0). Decision record: ADR-015.

## Why

"Post-it" is 3M's registered mark and collides in every search. "Verbnest"
was free on npm, pub.dev, GitHub and the .com/.dev/.app/.io domains when
checked (a trademark search in classes 9 and 42 is still the owner's job).

## Name map

| Old | New |
|---|---|
| PostIt (display) | Verbnest |
| `postit_core`, `postit_http`, ... (7 packages, `postit_app`) | `verbnest_*` |
| `postit` CLI | `verbnest` (plus a short `vn`) |
| `.postit` workspace files | `.verbnest`; `.postit` still opens |
| `com.omni.postit` (all platforms) | `com.omni.verbnest` |
| `POSTIT_VAR_*`, `POSTIT_HISTORY_DB`, `POSTIT_SHOTS_DIR` | `VERBNEST_*`; the first two old names still read |
| `X-PostIt-Example`, `X-PostIt-Delay` | `X-Verbnest-*`; old headers still accepted |
| snapshot manifest `postit.yaml` | `verbnest.yaml`; old name still imported |
| vault key `postit.secrets.<id>` | `verbnest.secrets.<id>`; old key read once and moved |
| app data folder (bundle-id based) | new folder; old one copied on first start |
| GitHub repo `bulhanb/postIt` | `bulhanb/verbnest`; remote `postIt` renamed to `origin` |

Not renamed on purpose: history in CHANGELOG.md and `.claude/` (they describe
past releases), the SQLite `application_id` (a file-format number), the
`flutter_secure_storage` keychain service name.

## Steps

1. Move directories and files whose path holds the old name (`git mv`).
2. Replace the name in tracked text files (ordered: bundle id, `postit_`,
   `POSTIT`, `PostIt`, `postit`), excluding the history files above.
3. Re-add compatibility: old extension, manifest, env vars, headers, vault
   key, data folder migration. Each has a test.
4. Regenerate `pubspec.lock`, ARB output; format, analyze, run every suite.
5. Rebuild macOS; commit, tag v0.43.0; rename the GitHub repo and remote; push.
6. Rename the local folder last, then update the paths in `.claude/`.

## Risks

- Bundle id change: stores treat it as a new app; macOS keychain asks once;
  signing identities and the Android upload key stay valid but the package id
  differs (a new Play listing). Owner decision, recorded in the ADR.
- CI badge, package URLs and the Flatpak/winget manifests point at the old
  repo name until updated in the same commit.
