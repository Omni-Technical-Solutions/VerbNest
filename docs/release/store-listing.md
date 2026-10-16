# Store listing (draft)

Shared text for every store. Edit here, then copy into each console.

- **Name:** VerbNest
- **Short description (80):** Local-first API client: send HTTP requests, keep everything on your device.
- **Category:** Developer Tools (Play, App Store, Microsoft Store, Flathub: Development)
- **Keywords (App Store, 100 max):** see `docs/release/app-store-post.md`. Drop `postman`: third-party names risk rejection.
- **Devices:** Android and iOS: phones and tablets only. In the Play Console under Release > Setup > Advanced settings > Form factors, do not add Wear OS, Android TV, Automotive or XR; in Device catalog, exclude Chromebooks (ChromeOS). In App Store Connect, tick iPhone and iPad only, untick "Make this app available on Mac/Apple Vision (iPhone and iPad apps)".
- **Feature to show:** the results table (screenshot `19-results-table` in `docs/release/screenshots/macos`; capture the same screen for the phone sets from the Table menu item if a listing slot is free).
- **Languages:** English only. App Store Connect: English (U.S.) as the only localisation. Play Console: English only. Android bundles only English resources (`localeFilters`); iOS and macOS declare `CFBundleLocalizations` = en.
- **Long description:** `distribution/fastlane/metadata/android/en-US/full_description.txt`
- **Support / source URL:** to be set by the owner
- **Privacy policy:** `docs/release/privacy-policy.md` (host it at a public URL)
- **Screenshots:** captured in `docs/release/screenshots/` (10 each unless noted): `iphone` 1206x2622 and `iphone-landscape` 2622x1206 (6.3" Dynamic Island), `ipad` 2064x2752 (13"), `android-phone` 1080x2424 and `android-phone-landscape` 2424x1080, `android-tablet` 2560x1600, `macos` 2880x1800 (18). Regenerate with `scripts/screenshots_devices.sh` and `scripts/screenshots_macos.sh`. Not captured: Windows 1366x768.
- **Feature graphic (Play):** 1024x500 PNG.
- **Age rating:** everyone; no user-generated content shared by the app, no ads.

## Review notes (App Store and Play)

- VerbNest sends the HTTP requests the user writes, to the addresses the user enters. That includes plain `http://` and self-signed servers, which is why cleartext traffic and an option to turn off certificate checks exist. Certificate checks are on by default.
- Scripts are JavaScript run in a sandboxed QuickJS engine with no file or network access except through the request API. They are written by the user and stored in the user's workspace; the app downloads no code.
- OAuth 2.0 sign-in opens the system browser and receives the redirect on `http://127.0.0.1:<random port>/callback`.
- **Why the app has the `com.apple.security.network.server` entitlement (macOS).** The app opens a listening socket in two places, both bound to the loopback address `127.0.0.1` only, never to an external interface, and only when the user starts them: (1) the OAuth 2.0 sign-in redirect receiver (`packages/verbnest_http/lib/src/oauth2_browser.dart`), which stops as soon as the redirect arrives, and (2) the optional local mock server in the collection runner (`packages/verbnest_runner/lib/src/mock_server.dart`), which serves a user's saved examples to their own tools. Without the entitlement the App Sandbox blocks both. Reply to the automated analysis with this text if it is raised again.
- **How to see both features (for the reviewer).** OAuth 2.0: open a request, Auth tab, choose OAuth 2.0 with the "Authorization code (browser)" grant, fill in the authorisation and token URLs and send; the app opens the system browser and waits for the redirect on `http://127.0.0.1:<port>/callback`. Mock server: open a request, save a response as an example (Examples, then Save current response), then open the collection menu, "Run…", "Mock server" in the app bar, and "Start"; the dialog shows the local address it serves on.
- **Entitlements (macOS, release):** `app-sandbox`, `network.client` (requests the user sends), `network.server` (the two loopback listeners above) and `files.user-selected.read-write` (open and save through the system file dialogs). Nothing else.
- No account is needed. Nothing is sent to the developer.
