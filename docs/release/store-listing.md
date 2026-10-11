# Store listing (draft)

Shared text for every store. Edit here, then copy into each console.

- **Name:** VerbNest
- **Short description (80):** Local-first API client: send HTTP requests, keep everything on your device.
- **Category:** Developer Tools (Play, App Store, Microsoft Store, Flathub: Development)
- **Keywords (App Store, 100 max):** see `docs/release/app-store-post.md`. Drop `postman`: third-party names risk rejection.
- **Long description:** `distribution/fastlane/metadata/android/en-US/full_description.txt`
- **Support / source URL:** to be set by the owner
- **Privacy policy:** `docs/release/privacy-policy.md` (host it at a public URL)
- **Screenshots:** not yet captured. Needed: phone (1080x1920), 7" and 10" tablet, iPhone 6.7" and iPad 13", macOS 1280x800, Windows 1366x768.
- **Age rating:** everyone; no user-generated content shared by the app, no ads.

## Review notes (App Store and Play)

- VerbNest sends the HTTP requests the user writes, to the addresses the user enters. That includes plain `http://` and self-signed servers, which is why cleartext traffic and an option to turn off certificate checks exist. Certificate checks are on by default.
- Scripts are JavaScript run in a sandboxed QuickJS engine with no file or network access except through the request API. They are written by the user and stored in the user's workspace; the app downloads no code.
- OAuth 2.0 sign-in opens the system browser and receives the redirect on `http://127.0.0.1:<random port>/callback`.
- **Why the app has the `com.apple.security.network.server` entitlement (macOS).** The app opens a listening socket in two places, both bound to the loopback address `127.0.0.1` only, never to an external interface, and only when the user starts them: (1) the OAuth 2.0 sign-in redirect receiver (`packages/verbnest_http/lib/src/oauth2_browser.dart`), which stops as soon as the redirect arrives, and (2) the optional local mock server in the collection runner (`packages/verbnest_runner/lib/src/mock_server.dart`), which serves a user's saved examples to their own tools. Without the entitlement the App Sandbox blocks both. Reply to the automated analysis with this text if it is raised again.
- **How to see both features (for the reviewer).** OAuth 2.0: open a request, Auth tab, choose OAuth 2.0 with the "Authorization code (browser)" grant, fill in the authorisation and token URLs and send; the app opens the system browser and waits for the redirect on `http://127.0.0.1:<port>/callback`. Mock server: open a request, save a response as an example (Examples, then Save current response), then open the collection menu, "Run…", "Mock server" in the app bar, and "Start"; the dialog shows the local address it serves on.
- **Entitlements (macOS, release):** `app-sandbox`, `network.client` (requests the user sends), `network.server` (the two loopback listeners above) and `files.user-selected.read-write` (open and save through the system file dialogs). Nothing else.
- No account is needed. Nothing is sent to the developer.
