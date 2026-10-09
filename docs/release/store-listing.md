# Store listing (draft)

Shared text for every store. Edit here, then copy into each console.

- **Name:** VerbNest
- **Short description (80):** Local-first API client: send HTTP requests, keep everything on your device.
- **Category:** Developer Tools (Play, App Store, Microsoft Store, Flathub: Development)
- **Keywords:** api, http, rest, postman, openapi, oauth, json, developer
- **Long description:** `distribution/fastlane/metadata/android/en-US/full_description.txt`
- **Support / source URL:** to be set by the owner
- **Privacy policy:** `docs/release/privacy-policy.md` (host it at a public URL)
- **Screenshots:** not yet captured. Needed: phone (1080x1920), 7" and 10" tablet, iPhone 6.7" and iPad 13", macOS 1280x800, Windows 1366x768.
- **Age rating:** everyone; no user-generated content shared by the app, no ads.

## Review notes (App Store and Play)

- VerbNest sends the HTTP requests the user writes, to the addresses the user enters. That includes plain `http://` and self-signed servers, which is why cleartext traffic and an option to turn off certificate checks exist. Certificate checks are on by default.
- Scripts are JavaScript run in a sandboxed QuickJS engine with no file or network access except through the request API. They are written by the user and stored in the user's workspace; the app downloads no code.
- OAuth 2.0 sign-in opens the system browser and receives the redirect on `http://127.0.0.1:<random port>/callback`.
- No account is needed. Nothing is sent to the developer.
