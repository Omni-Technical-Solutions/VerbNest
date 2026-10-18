# Plan: show the application version in Settings → About

Status: plan only, nothing changed yet. Planned release type: `minor` (a small
addition to an existing capability), so 0.64.5 → 0.65.0.

## Where things stand (v0.64.5+47)

- No code reads or shows the version. `apps/verbnest_app/pubspec.yaml` has no
  `package_info_plus`, and nothing calls `showAboutDialog`.
- Settings → About (`lib/src/settings_page.dart`, around line 49) has a single
  tile, "Open source licences". It opens `showLicensePage` with
  `applicationName` and `applicationLegalese` only, so the licence page shows
  no version either.
- The version already reaches every platform build: `scripts/build.sh` passes
  `--build-name=<VERSION> --build-number=<BUILD_NUMBER>`, and
  `scripts/bump_version.sh` / `scripts/next_build.sh` keep the pubspec in sync.
  Nothing needs to change in the build scripts.

## Goal

Settings → About shows "Version 0.64.5 (47)" on every platform (Android, iOS,
macOS, Windows, Linux), taken from the installed build and not from a
hard-coded string. The licence page shows the version too. Users can copy it
for bug reports.

## Design

1. **Source of truth: the installed app, via `package_info_plus`.** It reads
   the platform's own metadata (Android `versionName`/`versionCode`, iOS and
   macOS `CFBundleShortVersionString`/`CFBundleVersion`, Windows resource,
   Linux the Flutter bundle's `version.json`). That is exactly what the stores
   and `--build-name`/`--build-number` set, so it cannot drift from `VERSION`
   and `BUILD_NUMBER`.
   - Alternative rejected: generating a Dart constant from `VERSION` in a build
     step. It adds a build step and breaks when someone builds without the
     script; the plugin needs neither.
2. **State: one provider.** `appVersionProvider` (a `FutureProvider<AppVersion>`
   in `lib/src/state/app_info_state.dart`) wraps `PackageInfo.fromPlatform()`
   and returns a small value with `name` and `build`, plus a `label` getter:
   `0.64.5 (47)`. A provider is the pattern in the rest of `lib/src/state`, and
   tests override it.
3. **UI: a tile above "Open source licences" in the About card.**
   `ListTile` with key `app-version`, leading `Icons.info_outline`, title
   "Version", subtitle the label. While loading or if the lookup throws, the
   subtitle is empty (no spinner, no error; the row must never block Settings).
   Long-press or tap copies "VerbNest 0.64.5 (47)" to the clipboard and shows a
   snackbar "Version copied". Selectable text is the fallback if tap is needed
   for something else later.
4. **Licence page:** pass `applicationVersion: label` to `showLicensePage`, so
   the page header shows it as well.
5. **Strings** (`lib/l10n/app_en.arb`, English only per ADR-017):
   `aboutVersion` = "Version", `aboutVersionCopied` = "Version copied",
   `aboutVersionCopyHint` = "Tap to copy" (tooltip/semantic hint). Regenerate
   with `flutter gen-l10n`; `l10n_guard_test.dart` must stay green.

## Steps

1. Add `package_info_plus` to `apps/verbnest_app/pubspec.yaml`
   (`flutter pub add package_info_plus`). Check that it builds on all five
   platforms, in particular that the Linux build still works in the Ubuntu
   22.04 root (`docs/release/linux-build.md`) and that no new native
   dependency affects the F-Droid / Flatpak notes. Update
   `THIRD_PARTY_NOTICES.md` with `scripts/third_party_notices.py`.
2. Add `lib/src/state/app_info_state.dart` (provider and `AppVersion`).
3. Add the strings and regenerate l10n.
4. Add the tile and the `applicationVersion` argument in `settings_page.dart`.
5. Tests (below).
6. Docs: `CHANGELOG.md` entry "Change: Settings → About shows the version and
   build number"; `docs/spec/requirements.md` / `ux.md` if they list the
   About contents; `docs/release/store-listing.md` needs nothing.
7. Release per `docs/spec/roadmap.md` (Release workflow): analyze and tests
   green, commit `minor(settings): show app version in About (v0.65.0)`,
   `scripts/bump_version.sh minor`, annotated tag `v0.65.0`, then builds
   through `scripts/build.sh`. Pushing and publishing stay manual.

## Tests

- **Widget test** (`test/settings_about_version_test.dart`): override
  `appVersionProvider` with `0.64.5 (47)`; open Settings; the `app-version`
  tile shows "Version" and "0.64.5 (47)". Tapping it puts
  "VerbNest 0.64.5 (47)" on the clipboard (mock `SystemChannels.platform`) and
  shows the snackbar.
- **Failure case:** provider throws → tile still renders with an empty
  subtitle, no exception reaches the framework.
- **Existing suites:** `settings_english_only_test.dart`,
  `accessibility_test.dart` (tap target and semantics of the new tile),
  `overflow_matrix_test.dart` and `device_matrix_*` (the longer About card must
  not overflow at small sizes and large text), and the golden tests that
  include Settings (macOS only, regenerate and review the diff).
- **Real value check:** `PackageInfo.setMockInitialValues` is used in one test
  that builds the real provider, so the wiring (not only the override) is
  covered. On a release build, confirm by hand that the shown value equals
  `VERSION+BUILD_NUMBER` (Linux `.deb`, macOS DMG are the easiest to open).

## Risks

| Risk | Mitigation |
|---|---|
| Plugin returns an empty build number on some platform (known on Linux/Windows for dev runs without `--build-number`) | `label` falls back to the name alone when the build is empty; covered by a unit test |
| New plugin breaks the Linux jammy build or adds a native dependency | Step 1 builds all targets in CI before anything else is written |
| Golden diffs on Settings | Regenerate on macOS only (existing rule), review the diff |

## Out of scope

- Update checks, release notes in the app, a licence page redesign.
- Showing the git commit hash (no source for it in the build scripts yet).

## Open questions

1. Should the version also appear in the status bar or the window title on
   desktop? Default: no, Settings only.
2. Tap to copy, or a plain read-only row? Default: tap to copy.
