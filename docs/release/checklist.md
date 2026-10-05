# Store release checklist

What is ready in the repository and what only the account owner can do. Nothing here has been run against a real store.

## Ready
- App id and bundle id: `com.omni.postit` on every platform. Stores fix the id for good.
- Version and build number come from `VERSION` and `BUILD_NUMBER`; build with `scripts/build.sh`.
- Android release signing reads `apps/postit_app/android/key.properties` (`storeFile`, `storePassword`, `keyAlias`, `keyPassword`); without it the release is debug-signed.
- F-Droid / Play text and changelog layout: `distribution/fastlane/metadata/android/en-US/`.
- Flathub draft: `distribution/flatpak/` (manifest, metainfo, desktop file).
- winget templates: `distribution/winget/`.
- macOS: `scripts/package_macos.sh` (ad-hoc DMG) and `scripts/notarize_macos.sh` (Developer ID signing, notarisation, stapling).
- Listing text, review notes, privacy policy draft: `docs/release/`.

## Done on this machine (not yet uploaded anywhere)
- Android upload key created at `~/.postit-signing/upload-keystore.jks` (alias `upload`); passwords are in the gitignored `apps/postit_app/android/key.properties`. **Back both up now.** If the key is lost, Play can only reset it through support. `flutter build appbundle --release` produced a signed `com.omni.postit` bundle (version 0.25.0, code 4).
- iOS release build compiles with `--no-codesign`; the macOS DMG builds, is ad-hoc signed and its bundle id is `com.omni.postit`.
- Entitlements: macOS Release now also allows a local server (`network.server`), needed for the OAuth 2.0 browser redirect. `ITSAppUsesNonExemptEncryption` is false (only standard HTTPS/TLS), so App Store Connect will not ask the export question.

## Play Store, in order
1. Create a Play Console developer account (one-time fee; new personal accounts must run a closed test with 12 testers for 14 days before production).
2. Create the app with package name `com.omni.postit`; turn on Play App Signing and upload `apps/postit_app/build/app/outputs/bundle/release/app-release.aab` to an internal test track first.
3. Fill the store listing from `docs/release/store-listing.md`, host `privacy-policy.md` at a public URL, answer the data safety form (no data collected, none shared) and the content rating questionnaire.

## App Store, in order
1. Join the Apple Developer Program. In the developer portal register App ID `com.omni.postit` and create the app in App Store Connect (iOS and macOS share the id).
2. In Xcode open `apps/postit_app/ios/Runner.xcworkspace` and `macos/Runner.xcworkspace`, set your Team under Signing & Capabilities (automatic signing), then `flutter build ipa --release` and upload with Xcode Organizer or `xcrun altool`/Transporter. The macOS Mac App Store build needs the 3rd Party Mac Developer Application and Installer certificates.
3. Fill listing, screenshots, privacy ("Data Not Collected") and review notes from `store-listing.md`.

## Needs the owner
1. Google Play: developer account, `keytool -genkey` upload key, `flutter build appbundle --release`, Play App Signing, data safety form (no data collected), content rating.
2. F-Droid: merge request to `fdroiddata` with a build recipe for the tag; the app has no proprietary dependencies, but check `fjs` (Rust) builds from source in their build server.
3. App Store (iOS and macOS): Apple Developer Program, distribution certificates and profiles, `flutter build ipa`, App Store Connect listing, screenshots, review notes from `store-listing.md`. Sandbox entitlements for outgoing network and user-selected files need review.
4. Microsoft Store / winget: publisher account, MSIX packaging (`msix` package or Inno Setup), signing certificate, winget manifests with the real installer URL and SHA-256.
5. Flathub: pull request to `flathub/flathub`; replace the placeholder source URL and commit; a Linux machine to build and test the Flatpak.
6. Screenshots, public support URL, hosted privacy policy.
7. Windows and Linux builds have only been compiled in CI, never run by hand.
