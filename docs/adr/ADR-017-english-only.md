# ADR-017: English only

Status: accepted (v0.58.0 removed Arabic; v0.59.1 and v0.59.2 finish it)

## Context
VerbNest shipped English and Arabic. The owner decided to support English only on every platform.

## Decision
- One ARB file, `app_en.arb`; `AppLocalizations.supportedLocales` is `[en]`, guarded by `test/l10n_guard_test.dart`.
- The app pins `locale: const Locale('en')`, so a device in any language gets English strings and English Material labels, not a mix. The language-switching code and the Language setting are gone; a saved `language` value in an old workspace is ignored.
- Each platform declares it: Android `androidResources.localeFilters = ["en"]`; iOS and macOS `CFBundleLocalizations = (en)`; Windows and Linux have no language resources. Store listings are English only.

## Kept on purpose
- Strings in ARB with typed getters (not constants), and `flutter_localizations`/`intl`, which also give the framework widgets their English labels.
- Directional layout code and the widget-level right-to-left tests, so layout does not regress.

## Adding a language again
Add its ARB file, remove the pin to `en` (or add a setting), widen `l10n_guard_test.dart`, add the platform declarations and store listings, and test the layout in that language.

## Not covered
Programming languages for code generation and syntax colours, and Unicode in names, URLs and bodies (NFR-I18N-001), which stay.
