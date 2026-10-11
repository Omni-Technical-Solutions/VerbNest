# Plan: English only, on every platform

Status: plan only, nothing changed yet. Since v0.58.0 the app ships one string
file (`app_en.arb`). This plan finishes the job: no other language is offered,
claimed, bundled or reachable on any platform, and the code that existed only
to switch languages goes.

## Review: where things stand (v0.59.0)

Already English only:
- Strings: `lib/l10n/app_en.arb` is the only ARB; `AppLocalizations.supportedLocales`
  is `[en]`. Guarded by `test/l10n_guard_test.dart`.
- Settings: the Language control is gone. A device set to another language still
  gets English (`step22_test.dart`).
- Store text: `distribution/fastlane/metadata/android/en-US` is the only locale;
  `docs/release/store-listing.md` and `app-store-post.md` are English.
- Windows and Linux: no language resources.
- Xcode: `developmentRegion = en`, `knownRegions = (en, Base)` on iOS and macOS.

Still open (found by search):
1. **Dead language switching.** `lib/src/state/locale_state.dart`
   (`LocaleNotifier`, `localeProvider`) and `app.dart` line 31
   (`locale: ref.watch(localeProvider)`) can only ever return English. The saved
   `language` workspace setting is read, then ignored.
2. **Android does not declare English only.** `android/app/build.gradle.kts` has
   no locale filter, so libraries' string resources for dozens of languages ship
   in the AAB and Play can list them as supported languages.
3. **iOS and macOS do not declare it either.** Neither `Info.plist` has
   `CFBundleLocalizations`; the App Store infers the languages from bundled
   `.lproj` folders, and plugins and Flutter's own frameworks bring some.
4. **`flutter_localizations` and `intl` stay as dependencies.** They are still
   needed: they give Material and Cupertino widgets their English labels
   ("Cut", "Paste", date formats, back button tooltip) and `AppLocalizations`
   is generated on top of them. Removing them is not possible without
   replacing those widget strings.
5. **Docs still describe localisation as a goal:** `requirements.md` FR-APP-004
   ("... language") and FR-APP-005, `feature-inventory.md` line 173
   ("Localisation: Yes, P1"), `roadmap.md` ("localisation framework"),
   `implementation-plan.md` step 22 ("ARB localisation and RTL"),
   `architecture.md` i18n row, `README`/CHANGELOG mentions, and the older plans.

Not in scope (not languages of the app): programming languages in code
generation and syntax colouring, and Unicode in names, URLs and bodies
(NFR-I18N-001). Those stay.

## Decision to take first

Keep the ARB mechanism, or replace it with plain constants?
- **Keep ARB (recommended).** English strings stay in one file with typed
  getters, the guard tests keep working, and a language can be added later by
  adding an ARB file. Cost: the generator and two packages stay.
- **Replace with constants.** Removes `generate: true`, `l10n.yaml`, three
  generated files and the l10n guard, but touches about every widget file
  (about 700 string uses) for no user-visible gain, and makes a future language
  a rewrite. Not recommended.

The plan below assumes "keep ARB".

## Phases (one commit each, in this order)

### E1. Remove the language-switching code (patch, 0.59.1)
- Delete `locale_state.dart` and `locale: ref.watch(localeProvider)` from
  `app.dart`; keep `supportedLocales` and the delegates (they supply the
  English widget strings). Pin `locale: const Locale('en')` so a device in any
  language gets English labels everywhere (Material labels included), not a mix.
- Drop the unused `language` key from the workspace settings model if nothing
  reads it; leave an existing saved value untouched in old files (no migration).
- Tests: replace the two locale tests in `step22_test.dart` with one: with the
  device set to Arabic, French and Japanese in turn, the app builds in English
  (strings and Material labels) and left-to-right. Keep `l10n_guard_test.dart`.
- Done when: no reference to `localeProvider` or `LocaleNotifier`; analyze and
  tests pass.

### E2. Declare English only on each platform (patch, 0.59.2)
- **Android:** `defaultConfig { resourceConfigurations += "en" }` (or
  `androidResources { localeFilters += "en" }` on AGP 8.8+), so only English
  resources from libraries ship. Check the AAB with
  `bundletool dump resources` that no `values-xx` folder other than English is
  left, and that the app still starts (a missing resource crashes, so run the
  debug build on the emulator).
- **iOS and macOS:** add `CFBundleLocalizations = (en)` to both `Info.plist`
  files and keep `CFBundleDevelopmentRegion = en`. Check the built `.app` for
  stray `*.lproj` folders from plugins (`find ... -name "*.lproj"`) and list
  what remains; plugin folders for other languages are only removable with a
  build-phase script, so decide after seeing the list whether that is worth it.
- **Windows and Linux:** nothing to change; record in the checklist that they
  carry no language resources.
- **Stores:** App Store Connect: set English (U.S.) as the only localisation;
  Play Console: English only in the listing and store settings (Owner task).
- Done when: the built AAB, IPA and `.app` list English as their only language
  (verified with the commands above) and a debug run on Android is clean.

### E3. Documentation (chore)
- Rewrite FR-APP-004 and FR-APP-005, `feature-inventory.md` (Localisation: "No,
  English only by decision"), `roadmap.md`, `implementation-plan.md` step 22,
  `architecture.md` i18n row; add an ADR "English only" recording the
  decision, what was kept (ARB, directional layout, RTL widget tests) and how a
  language would be added back (ARB file, widen the guard test, store listings).
- Mention in `docs/release/store-listing.md` and `checklist.md` that listings are
  English only and where to set it in each store.

### E4. Release (chore)
- Rebuild the AAB, IPA and PKG with one build number, check the language
  declarations on the built packages, follow the release workflow; do not
  upload.

## Order and size

| # | Phase | Release | Size | Needs |
| --- | --- | --- | --- | --- |
| E1 | Remove switching code | patch | S | decision on ARB |
| E2 | Platform declarations | patch | S | Android emulator check |
| E3 | Docs and ADR | chore | S | none |
| E4 | Rebuild packages | chore | S | E1 and E2 |

## Owner tasks

- App Store Connect: keep English (U.S.) as the only localisation; Play
  Console: English only. Removing a store localisation that was never added
  needs no action; check there are none.
- Decide ARB vs constants (above).

## Risks

- Android locale filtering can drop a string a library looks up for the device
  language and fall back oddly; the English fallback exists in every library,
  so the risk is low, but the emulator run is part of "done".
- Pinning `locale` to English means a right-to-left device language no longer
  mirrors the app; this is intended (English only) and the directional layout
  code stays so a future language works.
