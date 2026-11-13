# Mac App Store: the `network.server` entitlement message (again)

Status 2026-11-13: reviewed; plan written; nothing changed in the app. This is the second time App Review raises it (first: F1 in `remaining-actions-plan.md`, answered with the review notes in `docs/release/store-listing.md`).

## What App Review said

An automated analysis found `com.apple.security.network.server` in the app but no matching functionality. They offer two actions: remove the entitlement if it is not needed, or reply and describe how the app uses it, and add that to App Review Information in App Store Connect.

## Review

- `apps/verbnest_app/macos/Runner/Release.entitlements` holds exactly four keys: `app-sandbox`, `network.client`, `network.server` and `files.user-selected.read-write`. `DebugProfile.entitlements` adds only `cs.allow-jit` (debug builds; Flutter needs it). Nothing else is unexplained, so there is nothing else to trim.
- The app really does listen. Searching the code for listening sockets (`HttpServer.bind`) finds two, both on `127.0.0.1` only, both started by the user:
  1. the OAuth 2.0 sign-in redirect receiver, `packages/verbnest_http/lib/src/oauth2_browser.dart` (random port, stops when the redirect arrives);
  2. the mock server in the collection runner, `packages/verbnest_runner/lib/src/mock_server.dart` (serves saved examples).
- Under the App Sandbox a process may not `bind` and `listen` without `network.server`, even on loopback (`network.client` covers outgoing connections only). Removing the entitlement would make both features fail with a permission error in the Mac App Store build: browser sign-in for OAuth 2.0 (FR-AUTH-003) and the mock server.
- The automated check cannot see these: both sit behind several clicks, and nothing runs at launch. That is why the warning appears even though the entitlement is justified.

## Decision

Keep the entitlement and answer with the explanation (Apple's second option). Removing it would take away two documented features from the Mac App Store build for no gain. The fallback (a build without them) stays in `remaining-actions-plan.md` F1 and needs the owner's decision.

## Steps

1. **Reply in Resolution Center (owner, now).** Paste the text below. It is short because the full notes go in step 2.

   > VerbNest is a local API client. It needs `com.apple.security.network.server` because it opens a listening socket in two places, both bound to the loopback address 127.0.0.1 only (never an external interface) and only when the user starts them: (1) the OAuth 2.0 browser sign-in receives the redirect on `http://127.0.0.1:<random port>/callback` and closes the socket when the redirect arrives; (2) the optional mock server in the collection runner serves the user's saved example responses on a local port so their own tools can call them. Without the entitlement the App Sandbox blocks both. Steps to see each are in the App Review Information notes, and a screen recording of both is attached. The app uses no other entitlements beyond the sandbox, `network.client` and `files.user-selected.read-write`.

2. **App Review Information (owner, now).** In App Store Connect, App Information for the version under review > App Review Information > Notes, paste the "Review notes" block from `docs/release/store-listing.md` (it already has the explanation, the reviewer steps with the real labels, and the entitlement list). The reviewer steps there match the app: Auth tab > "Authorization code (browser)"; Examples > "Save current response"; collection menu > "Run…" > "Mock server" > "Start". If the field already has the old text, replace it; Apple reads this field, not the repository.
3. **A Mac recording for the reviewer (agent, optional, recommended).** Reuse the physical-device approach (`docs/release/app-review-recording.md`) on this Mac: a macOS integration test that starts the real app on a throwaway workspace, saves an example, starts the mock server ("Serving on http://127.0.0.1:<port>"), sends a request to that address from the app and shows the 200 answer, then opens OAuth 2.0 auth with a loopback receiver, and a screen recording (`ffmpeg -f avfoundation` on "Capture screen 0" or `screencapture -v`) of the run. Attach it in the reply and in the review notes. About half a day, including the recording script. No app change.
4. **Resubmit (owner).** Submit the current build (0.65.4, macOS build via the `.pkg`; the 0.65.4 PKG still has to be exported once Xcode is signed in) with the notes. No new code is needed, so no version bump. If the message came on a build already in review, reply in the same thread instead.
5. **If App Review still refuses (decision for the owner).** Offer the fallback: a compile-time flag (`--dart-define=MAS=true`) that removes `network.server` from the Mac App Store entitlements and hides browser sign-in and the mock server in that build only; the DMG, Windows, Linux, Android and iOS keep them. It removes real functionality from one store, so it is not the default.

## Risks

- A repeat of the automated message after a reply is normal; a human reviewer then reads the notes. The recording is there so they do not have to find the features themselves.
- The PKG for 0.65.4 is not built yet (Xcode sign-in); the reply can go out before that.
- The App Review Information field is per app version: a new version starts with the old text, so check it each time.
