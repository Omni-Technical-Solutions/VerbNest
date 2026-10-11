# Remaining actions plan

Status at v0.57.0 (branch and tags pushed; DMG 0.57.0+18 built; store packages
in `~/Downloads` are still 0.53.0+17). This plan lists everything still open,
who can do it, and in what order. CI is out of scope: the GitHub Actions
failures are a hosting matter and are left alone.

Items marked **Agent** can be done in a session like this one. Items marked
**Owner** need your accounts, certificates, devices or a decision, and cannot
be done by the agent. Each Agent phase is one release: its own commit, version
bump where the type calls for it, CHANGELOG entry, context update and tests
(`.claude/commands/phase-commit.md`).

## Start here: two items first

These two come before everything else. The App Store question is open now, and
removing Arabic ships in the build that answers it.

### F1. App Store: the `network.server` entitlement warning - steps 2 and 3 done (v0.58.0); 1 and 4 are the Owner's

The App Store's automated analysis says the Mac build has the
`com.apple.security.network.server` entitlement but no matching functionality.
It is a real requirement, so the answer is to keep it and explain it (the
alternative is below).

Why it is needed: the app opens a listening socket in two places, both bound to
`127.0.0.1` only and only when the user starts them. Without the entitlement the
App Sandbox blocks both.

- the OAuth 2.0 redirect receiver, `packages/verbnest_http/lib/src/oauth2_browser.dart`
  (`HttpServer.bind(loopbackIPv4, 0)`; it stops when the redirect arrives);
- the optional local mock server in the collection runner,
  `packages/verbnest_runner/lib/src/mock_server.dart`.

Steps:

1. **Respond (Owner, now).** In the Resolution Center or App Review notes for
   the build under review, paste the explanation saved in
   `docs/release/store-listing.md` (review notes, written in commit `a8a49ec`).
2. **Make it easy to verify (Agent, chore).** Add reviewer steps to the same
   review notes so a reviewer can see both features, using the real labels:
   for OAuth, open a request, Auth tab, choose OAuth 2.0 with the
   "Authorization code (browser)" grant, fill in the URLs and send; the app
   opens the system browser and waits for the redirect on
   `http://127.0.0.1:<port>/callback`. For the mock server, first save a
   response as an example ("Examples", then "Save current response"), then open
   the collection menu, "Run…", then "Mock server" in the app bar and "Start",
   and open the address it shows. Check the wording against the app before
   saving it.
3. **Keep the entitlements minimal (Agent).** Confirm `Release.entitlements`
   lists only what the app uses (sandbox, `network.client`, `network.server`,
   `files.user-selected.read-write`) and that `DebugProfile.entitlements` adds
   nothing unexplained.
4. **Resubmit with the next build (Owner, after F2 and A1).** The build with
   Arabic removed (0.58.0) is the one to submit, with the same review notes.
   If Apple answers the existing build first, reply in the same thread.

Fallback, only if Apple rejects the explanation: drop the entitlement from the
Mac App Store build and switch off the two features there (OAuth browser
sign-in and the mock server), behind a compile-time flag so the DMG and other
platforms keep them. That removes real functionality, so it is a decision for
you (see the list at the end), not a default.

Done when: the notes with reviewer steps are in the repository, the Owner has
replied, and the resubmitted build is in review without the warning.

### F2. Remove Arabic language support (minor, 0.58.0) - done

Decided: the app drops Arabic and ships in English only. It is a user-facing
removal, so it is a minor release with a CHANGELOG "Removed" entry.

What changes:

- **Translations.** Delete `lib/l10n/app_ar.arb` and the generated
  `app_localizations_ar.dart`, then run `flutter gen-l10n` so
  `supportedLocales` is English only. Drop the Arabic-parity rule from
  `test/l10n_guard_test.dart` (it checks every key exists in both files).
- **Settings.** Remove the Language control from `settings_page.dart`: with one
  language it has nothing to choose. Keep `localeProvider`, but make it ignore a
  saved language the app no longer ships, so a workspace that had `ar` selected
  opens in English and nothing breaks. No data migration is needed.
- **Tests.** Remove the Arabic-locale tests in `step22_test.dart` (translated
  labels and right-to-left layout, language setting switches the UI), replace
  them with one test that a saved `ar` falls back to English, and remove the
  right-to-left drawer test in `adaptive_layout_test.dart` that sets the `ar`
  locale. Remove the Arabic golden (`layout-compact-ar.png`) and its case in
  `layout_goldens_test.dart`.
- **Screenshot harness.** Remove the Arabic font registration (Geeza Pro) and the
  `language: 'ar'` path from `tool/screenshots_test.dart`, and the "Arabic
  screenshot omitted" note in `docs/release/checklist.md`.
- **Store copy and docs.** App Store description: change "English and Arabic with
  full right-to-left layout" (`docs/release/app-store-post.md`) to English only,
  and re-check the Play description and `store-listing.md`. Search `README.md`,
  `docs/spec/requirements.md`, `ux.md` and `feature-inventory.md` for
  internationalisation and right-to-left claims and correct them.
- **Keep.** Directional layout code (`EdgeInsetsDirectional`, `PositionedDirectional`,
  `AlignmentDirectional`) and the widget-level right-to-left tests that wrap a
  widget in `Directionality` (`rtl_code_test.dart`, the edge fade in
  `scroll_cues_test.dart`). They cost nothing, keep the layout correct if a
  right-to-left language is added later, and do not depend on Arabic.
- **History stays.** Earlier CHANGELOG entries and ADRs that mention Arabic are
  history and are not rewritten.

Done when: no Arabic string, font or locale remains in the app or its tests,
`flutter gen-l10n` and the analyzer are clean, all tests pass, and the store
text says English only.

Risk: a person who chose Arabic loses it. Say so plainly in the release notes.
If the Play Console or App Store listing was ever localised to Arabic, remove
that listing language there too (Owner, part of A4).

## Where things stand

| Area | State |
| --- | --- |
| UI modernisation (Material 3) | Done, v0.46.1 to v0.53.0 |
| Mobile adaptive UI | Done, v0.53.1 to v0.57.0 |
| macOS DMG | 0.57.0+18, universal, signed, **not notarised** |
| Store packages (AAB, IPA, PKG) | **0.53.0+17**, built and signed, **not uploaded** |
| GitHub release | v0.46.0 only; v0.47.0 to v0.57.0 have tags but no release |
| Store listing text, keywords, screenshots, feature graphic | Ready (screenshots for 7 sets) |
| Real-device checks | **None run** |
| App Store review (Mac) | **Open**: `network.server` entitlement warning (F1) |
| Arabic language support | Shipped today; **to be removed** (F2) |

## A. Release and publishing

### A1. Rebuild the store packages for 0.57.0 (Agent, chore)

Why: the packages on disk predate the whole mobile plan.

- Reserve one build number, build the AAB (with `rustup` on `PATH`), the IPA and
  the Mac App Store PKG, and the DMG with `SKIP_BUILD=1`, all with the same
  number, following `docs/release/checklist.md`.
- Verify each: AAB package name and upload-key fingerprint, IPA bundle id and
  version, PKG signing certificate and universal binary.
- Done when: four artefacts in `~/Downloads` named `...0.57.0+<n>...`, and the
  build number committed as `chore(release)`.
- Risk: the Android Rust build takes about 10 minutes; Xcode export needs the
  signed-in Apple account.

### A2. GitHub releases (Agent, chore)

- Create release v0.57.0 with the universal DMG, and short notes that summarise
  v0.47.0 to v0.57.0 from `CHANGELOG.md` (the older tags stay as plain tags).
- Say plainly in the notes that the DMG is signed but not notarised.
- Done when: the release page shows one DMG and the notes.
- Needs your go-ahead to publish (it is public).

### A3. Notarise the DMG (Owner, then Agent)

- Owner: create a **Developer ID Application** certificate (only Apple
  Distribution and Developer ID Installer are installed now) and a notary
  keychain profile (`xcrun notarytool store-credentials`).
- Agent: run `scripts/notarize_macos.sh`, which has never been run end to end,
  fix what breaks, and replace the DMG in the GitHub release.
- Done when: `spctl -a -vv` accepts the app on a clean Mac without
  right-click, Open.

### A4. Upload to the stores (Owner)

- Google Play Console: AAB, feature graphic
  (`distribution/fastlane/metadata/android/en-US/images/featureGraphic.png`),
  screenshots (`android-phone`, `android-tablet`, optional landscape set),
  listing text, data safety form (no data collected), content rating, privacy
  policy URL, support URL.
- App Store Connect: IPA through Transporter, screenshots (`iphone` 6.3",
  `ipad` 13", `macos`), promotional text, description and keywords from
  `docs/release/app-store-post.md`, privacy answers ("Data Not Collected"),
  review notes from `docs/release/store-listing.md`.
- Mac App Store: the PKG through Transporter, with the `macos` screenshots (this
  is the F1 resubmission).
- Done when: each store shows a build in review.

### A5. Hosting and legal (Owner)

- Host `docs/release/privacy-policy.md` at a public URL and set a support URL
  (both are still blank in `store-listing.md`).
- Run the trademark search for "VerbNest" (classes 9 and 42), open question 8.
- Done when: both URLs are in the store forms and the search result is recorded
  in `open-questions.md`.

### A6. Refresh the release documents (Agent, chore)

- `docs/release/store-listing.md` still says screenshots are "not yet
  captured" and lists old sizes; `docs/release/checklist.md` still describes
  versions 0.25.0 and 0.46.0 in places. Bring both up to date, and re-read
  `app-store-post.md` against what shipped (the drawer, status bar, tabs,
  Material You on Android, landscape).
- Done when: no document names a version or state that is no longer true.

## B. Checks that need real devices (Owner)

The agent can prepare but not run these. Use `docs/release/device-checklist.md`
and record the results at its bottom.

- B1. Run the checklist on one small phone, one large phone, one tablet and a
  foldable if available, in portrait and landscape.
- B2. VoiceOver and TalkBack: send a request without looking.
- B3. Android 14 and up: predictive back, transparent navigation bar, Material
  You colours (Android 12 and up) with "Use system colours" on.
- B4. iOS: swipe-back, haptics on Send and Copy, the Dynamic Island and home bar
  clearance, Dynamic Type at the largest setting.
- B5. macOS: confirm the native menu bar (VerbNest, File, Edit, Request, View,
  Window) in a running window. The agent's attempt was blocked by an
  Accessibility prompt; either grant it once or check by eye.
- B6. Windows and Linux: never run by hand (only compiled in CI before). Build
  and open the app on each, send a request, open the menus.
- Done when: the checklist has one filled result block per run. Any problem
  found comes back as an Agent fix (a patch release).

## C. Engineering (Agent)

### C1. Close the test-matrix gaps (patch)

Not covered by the device matrix yet: the import dialog, the environments
editor with the keyboard up, settings with the keyboard up, the examples dialog
and workspaces dialog at 280 to 320 pt.

- Add them to `test/device_matrix_screens_test.dart`, run, and fix what
  overflows with the existing patterns (`ScrollIfShort`, `AdaptiveDialog`,
  stacked rows).
- Done when: the matrix includes them and passes with empty known-failure maps.

### C2. Variables quick-look as a detail sheet (patch)

- Move `_QuickLook` in `env_selector.dart` onto `showDetail()` so it is a
  bottom sheet on phones like timings and TLS.
- Done when: a test shows the sheet on a phone and the dialog on desktop.

### C3. Replace the iOS launch image placeholder (patch)

- Flutter warns "launch image is set to the default placeholder". Add a branded
  launch screen (logo on the surface colour, light and dark) and check that the
  App Store validation no longer warns.
- Done when: `flutter build ipa` prints no launch image warning.

### C4. Code view soft wrap (minor, needs a decision)

- The code view uses a fixed row height for virtualised rows, so wrapping needs
  a different approach. Proposed: a wrap toggle that renders wrapped lines for
  responses up to a size cap (for example 2000 lines) and keeps the horizontal
  scroll above it, measuring line height with `TextPainter`.
- Done when: toggling wrap on a long JSON line shows it across several lines,
  folding and search still work, and a large response stays fast.
- Risk: search highlights and fold arrows assume one row per line.

### C5. Swipe between Request and Response (minor, needs a decision)

- Optional: a `PageView` behind the existing segmented switch, with the swipe
  restricted to the switch's edge zones so it does not fight horizontal scrolls
  in the panes. Skip if you prefer the switch alone.
- Done when: a swipe moves between the panes and the tab selection survives.

### C6. Bring the specification up to date (chore)

- `docs/spec/ux.md` still describes breakpoints of 600 and 1200, a rail with no
  drawer and no status bar. Update it to the shipped behaviour: the five width
  classes, the three height classes, the permanent drawer from 1200 dp, the
  status bar, preview and pinned tabs, the pinned URL bar and folding toolbar,
  and the adaptive dialogs and sheets.
- Update `README.md`, `feature-inventory.md` and `roadmap.md` where they list
  UI capability, and add a short ADR for "scroll and fold chrome rather than one
  page scroll" (decided in the mobile plan).
- Done when: `ux.md` matches what a person sees.

## D. Older open items (re-verify first)

These come from earlier notes in `.claude/context.md` and
`remaining-work-plan.md`. Some may have been finished since; check each against
the code before starting. None is urgent.

- Quality: no importer fuzzing or size limits in the UI; no large-workspace
  profiling; the sidebar tree rebuild cost is untested at thousands of nodes.
- Networking: HTTP/2 beyond what is present, PAC and NTLM proxies (not
  supported), mock server using saved examples.
- Verification debt: real browser launch for OAuth with a real identity
  provider; the network tests on iOS and Android; real corporate proxies.

Proposed handling: spend one session on a short audit that turns each into
"done", "open" or "drop", then plan the open ones.

## Order

| # | Item | Who | Size | Depends on |
| --- | --- | --- | --- | --- |
| 1 | F1.1 reply to App Review with the explanation | Owner | S | none (do it now) |
| 2 | F2 remove Arabic (0.58.0) | Agent | M | none |
| 3 | F1.2, F1.3 reviewer steps and entitlement check | Agent | S | none; can ride with item 2 |
| 4 | C1 matrix gaps | Agent | S | none |
| 5 | C2 quick-look sheet | Agent | S | none |
| 6 | C3 launch image | Agent | S | none |
| 7 | C6 spec update | Agent | S | 2 (so it states English only) |
| 8 | A6 release documents | Agent | S | 2 |
| 9 | B1 to B6 device checks | Owner | M | a build to test |
| 10 | A1 rebuild packages (after any fixes from 9) | Agent | M | 2, 4 to 6, 9 |
| 11 | F1.4 resubmit the Mac build | Owner | S | 10 |
| 12 | A3 notarise | Owner then Agent | S | certificate |
| 13 | A2 GitHub release | Agent | S | 10, 12 |
| 14 | A5 hosting and legal | Owner | S | none |
| 15 | A4 store uploads (iOS and Play; Mac is item 11) | Owner | M | 10, 14 |
| 16 | C4, C5 optional features | Agent | M | decisions |
| 17 | D audit | Agent | S | none |

Items 2 and 3 ship together as 0.58.0 (a minor release, because a language is
removed). Items 4 to 6 follow as 0.58.1. Device checks should happen on a build
that contains all of these, so rebuild the packages (item 10) once, not before.

## Decisions needed from the owner

- Soft wrap in the code view (C4): build it with the size cap, or leave long
  lines scrolling sideways with the visible scrollbar.
- Swipe between Request and Response (C5): add it, or keep the switch only.
- Whether a GitHub release should be created for every minor version or only the
  latest (A2).
- Who runs the device checks and when (B).
- F1 fallback: if Apple rejects the explanation, whether to drop the entitlement
  from the Mac App Store build and lose OAuth browser sign-in and the mock
  server there, or to keep arguing the case.
- F2: whether the right-to-left-safe layout code stays (recommended: yes).

## Not in scope

CI and GitHub Actions, web, a hosted sync service, telemetry, and new product
features beyond the list above.
