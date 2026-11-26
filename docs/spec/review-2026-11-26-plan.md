# Review of 0.73.1 and plan to address it (2026-11-26)

Status 2026-11-26: R1 to R7 implemented in 0.73.2 (R1 Linux job is a pin plus diagnostics, to be confirmed by CI; R2 left out the admin-enforcement setting, which is the owner's call; R6 fixed `no_motion_audit_test.dart` only, the 8 remaining hit-test warnings are in the device-matrix tests where a keyboard or overlay blocks the tap on purpose; R7 closed the stale markers, the archive split of `context.md` is not done). R8 is not started.

Scope of the review: repository state at `80d1fa8` (0.73.1, build 71): CI and branch protection, the dependency audit, the gates, the TLS / pinning / keystore code added in 0.65 to 0.73, tests, release process, docs. Evidence is from running the checks and reading the code and the CI logs; nothing was changed.

## What is healthy

- `dart analyze` and `flutter analyze`: no issues. Complexity gate: 972 functions, 413 classes, 214 files, 0 allowlisted, all within the limits (longest function 88 of 90 lines, so the headroom is thin).
- Package tests all pass locally: cli 39, core 171, http 221, import 60, runner 33, script 19, storage 66. App tests: see "Open" below.
- Secrets: client keys, passphrases and the proxy password live in the secret store, not in the network JSON; exports are sealed with PBKDF2 + AES-256-GCM; no key or certificate files are tracked in git; gitleaks passes in CI.
- Trust switches (`onBadCertificate`, `badCertificateCallback`) are only set from the explicit "do not verify" setting. The keystore relay listens on 127.0.0.1 only, accepts one connection and closes (documented residual risk in the threat model).

## Findings

Severity: **High** blocks trust in the release process; **Medium** a real defect or gap; **Low** hygiene.

### H1. CI on `main` has been red for 13 days (since 2026-11-13) and releases were cut on red
- Last green run: 2026-11-01. About 25 consecutive failed runs on `main`, including every release from 0.66.0 to 0.73.1.
- Two causes, not one:
  1. `packages (windows-latest)` has failed on every push since 2026-11-25. Cause: my test helper `_der` in `packages/verbnest_http/test/ca_check_test.dart` splits PEM on `\n`, so on Windows (CRLF from `openssl`) a `\r` reaches `base64Decode` ("Invalid character"). The shipped parser is fine (it strips all whitespace); only the test is wrong. Introduced in 0.73.0, so it also hid in the 0.73.0 and 0.73.1 releases.
  2. `build (linux)` failed on every run from 2026-11-23 to 2026-11-24 while installing packages on the runner image (`ubuntu-latest` is now Ubuntu "resolute"); not yet diagnosed. Since 2026-11-25 the `build` matrix is **skipped** because the Windows job fails first, so the Android and Linux CI builds have not run at all for 2 days.
- `main` is protected with 8 required checks, but admins are not enforced and the owner pushes straight to `main`, so red checks never blocked a push.

### M1. Dependency audit is red, and the reviewed-exception window is closing
- Scheduled audit failed on 2026-11-23 (and on dependabot PRs): two new advisories in the `fjs` 3.3.2 lockfile, RUSTSEC-2026-0543 (chrono 0.4.45, no fix) and RUSTSEC-2026-0592 (url 2.5.8, fixed in 2.5.9). Same reasoning as the other 25 ignored advisories (no JS builtins are enabled) but they are not yet in `osv-scanner.toml`.
- All 25 existing ignores expire on 2026-12-31, 35 days away; `fjs` 3.3.2 was the latest release when last checked. Dependabot PRs (riverpod 3.5.0, crypto 3.0.8) failed the audit and are unmerged.
- 34 locked packages are behind, 1 constrained below a resolvable version (`dart pub outdated`).

### M2. WebSocket/SSE pinning (0.72.0) has gaps beyond the documented one
In `realtime.dart` `_checkServerPin`:
- Fails open when the server certificate cannot be parsed (`on CertFormatException {}`): a pinned host with an unreadable certificate is allowed. The request path should be checked for the same behaviour; for a pin, unreadable should mean refuse.
- The probe does not use a keystore identity (the pre-handshake has no relay), so a server that requires a client certificate during the handshake may fail the probe before the real connection; untested.
- `Socket.connect` result is not closed if `SecureSocket.secure` throws (leaked socket until GC).
- Known and documented: two handshakes (a swapping server is not caught) and no pinning through a proxy.

### M3. The review gate is advisory
`.claude/.reviewed` is a self-reported hash and `git commit --no-verify` skips the git hook. The gate catches mistakes, not intent. Also: the pre-commit gate runs the whole app test suite on every commit, including `chore(release)` commits that only change `BUILD_NUMBER` and the pubspec (about 8 minutes each in this release), which pushes toward bypassing it.

### M4. Build number collision between machines
Build 70 was used by the 0.73.0 Windows/Linux builds on one machine while 0.73.1 was being built on another (fixed by renumbering 0.73.1 to 71). `BUILD_NUMBER` is only unique per checkout; nothing stops two machines taking the same number.

### L1. Test hygiene
- `no_motion_audit_test.dart` taps a widget at an off-screen offset (hit-test warning: "Offset(494.5, -22.0) ... would not hit test"); the tap silently misses, so that step of the audit tests nothing.
- Platform-conditional tests (`openssl`-dependent) skip silently (`markTestSkipped`); the CA tests would pass vacuously on a runner without `openssl`.
- `verbnest_keystore` has no Dart tests; its native code (Swift, Java, C++) is covered only by device integration tests that are run by hand.

### L2. Docs and context drift
- `.claude/context.md` has stale pending markers (line 20 "Release via ... 0.68.0", lines 145-148 phases L-O, all done in 0.73.0) which trigger the "resume" prompt at session start.
- `docs/spec/certificate-upload-plan.md` status line says phases L to O implemented; `docs/spec/remaining-work-plan.md` should be rechecked against 0.73.x.
- Context and several docs are large single files (`context.md` is far beyond what is read at session start).

### L3. Release coverage gaps (known, not new)
- No Linux/Windows installers or winget manifest for 0.73.1 (0.73.0 has both; winget PR #451601 still open).
- iOS device keystore test and Linux/Windows keystore sources not yet verified on hardware.
- 0.73.1's fix for the disabled Add button was inferred, not reproduced on the owner's file.

### App tests
`flutter test` in `apps/verbnest_app`: 719 passed, 0 failed (1 min 58 s). The log has 36 "hit test"/`warnIfMissed` warning lines, so the off-screen tap in L1 is likely more than one step; R6 counts them per file before fixing.

## Plan

Each step is one phase-commit; order is by risk. "Fix" bumps the patch version; chore does not bump.

### Phase R1: make CI green again (fix, 0.73.2) — High
1. Fix `_der` in `ca_check_test.dart`: split on `\r?\n` (or strip `\r`); add a CRLF-PEM case to `checkCaCertificates` tests so the production behaviour is pinned.
2. Re-run `packages (windows-latest)` locally where possible and on CI; confirm all 8 required checks and that the `build (android)` and `build (linux)` jobs now start.
3. Diagnose `build (linux)` from a fresh log (Ubuntu "resolute" package names / `libglycin` dependency pull); pin the runner (`ubuntu-24.04`) if the image change is the cause.
4. Done when: one fully green `ci.yml` run on `main`, including both build jobs. Record it in context.md.

### Phase R2: stop shipping on red (chore) — High
1. Release script/checklist (`docs/release/checklist.md`, `phase-commit` step 8): a release is not tagged or published unless the latest `main` CI run is green (`gh run list --branch main --limit 1`).
2. Decide with the owner: enforce branch protection for admins (so required checks apply to the owner's pushes) or keep direct pushes and rely on the checklist step. Recommendation: enforce admins and push through short-lived PR branches.
3. Skip the full test suite in the pre-commit gate when the staged diff is only `BUILD_NUMBER`/pubspec/docs (analyse + complexity only); keep the full suite for code changes.

### Phase R3: dependency audit (chore) — Medium
1. Add RUSTSEC-2026-0543 and RUSTSEC-2026-0592 to `osv-scanner.toml` with the same reason and an expiry; check whether `fjs` has a newer release or a `url` 2.5.9 bump.
2. Before 2026-12-31: re-check all 25 exceptions against a new `fjs` release; extend only with a fresh reason, or update `fjs`.
3. Merge or close the failing Dependabot PRs after the audit passes; run `dart pub upgrade --major-versions` in a branch and see what breaks.

### Phase R4: pinning hardening for WebSocket/SSE (fix, 0.73.3) — Medium
1. A pinned host whose certificate cannot be parsed refuses the connection (and the request path gets the same check and a test).
2. Close the raw socket if `SecureSocket.secure` throws.
3. Test the pre-handshake against a server that requires a client certificate and against a keystore entry; either make the probe use the same identity or document and surface a clear message.
4. Optional later: replace the pre-handshake with a pin check on the real connection (`HttpClient.badCertificateCallback` only fires on failures, so this needs `SecureSocket` ownership) to remove the two-handshake gap.

### Phase R5: build-number uniqueness (chore) — Medium
`scripts/next_build.sh` fetches `origin/main` and takes `max(BUILD_NUMBER on origin, local) + 1`, and `build.sh` refuses to build with a stale `BUILD_NUMBER`. Document that the builds of one version must come from one machine.

### Phase R6: test hygiene (chore) — Low
1. Fix the off-screen tap in `no_motion_audit_test.dart` (scroll into view first, and make `warnIfMissed` fatal in that file).
2. Make `openssl`-dependent tests fail (not skip) when `CI=true` and `openssl` is missing.
3. Decide whether `verbnest_keystore` gets a Dart unit test layer (method-channel fakes).

### Phase R7: docs and context tidy-up (chore) — Low
Close the stale ⏳ markers in `context.md` (lines 20, 145-148), move older entries to an archive file so the session-start read stays small, and recheck `remaining-work-plan.md`.

### Phase R8: remaining releases (feature work, owner decides) — Low
Linux `.deb` and Windows installer and winget manifest for the next version after R1 (build from green `main`); iOS device keystore test; Linux/Windows keystore verification.

## Suggested order
R1 first (it also verifies the Android and Linux CI builds that have not run for 2 days), then R2 and R3 together, then R4, then R5 to R7. Release 0.73.2 after R1 only.
