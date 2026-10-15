# Store release checklist

What is ready in the repository and what only the account owner can do. Nothing here has been run against a real store.

## Ready
- App id and bundle id: `com.omni.verbnest` on every platform. Stores fix the id for good.
- Version and build number come from `VERSION` and `BUILD_NUMBER`; build with `scripts/build.sh`.
- Android release signing reads `apps/verbnest_app/android/key.properties` (`storeFile`, `storePassword`, `keyAlias`, `keyPassword`); without it the release is debug-signed.
- F-Droid / Play text and changelog layout: `distribution/fastlane/metadata/android/en-US/`.
- Flathub draft: `distribution/flatpak/` (manifest, metainfo, desktop file).
- winget templates: `distribution/winget/`.
- macOS: `scripts/package_macos.sh` (signed DMG with Apple Distribution cert; override with `SIGN_IDENTITY`) and `scripts/notarize_macos.sh` (Developer ID Application signing, notarisation, stapling — needs a Developer ID Application certificate, not yet on this machine).
- Listing text, review notes, privacy policy draft: `docs/release/`.

## Done on this machine (not yet uploaded anywhere)
- Android upload key created at `~/.verbnest-signing/upload-keystore.jks` (alias `upload`); passwords are in the gitignored `apps/verbnest_app/android/key.properties`. **Back both up now.** If the key is lost, Play can only reset it through support. `flutter build appbundle --release` produced a signed `com.omni.verbnest` bundle (rebuild per release; the version and build number come from `VERSION` and `BUILD_NUMBER`).
- iOS release build compiles with `--no-codesign`; the macOS DMG builds, is signed with the Apple Distribution certificate (Omni Technical Solutions Pty Ltd, team NYY6MADXHV, hardened runtime + timestamp + entitlements) and its bundle id is `com.omni.verbnest`.
- Entitlements: macOS Release (sandbox, network.client, network.server, user-selected files) also allows a local server (`network.server`), needed for the OAuth 2.0 browser redirect. `ITSAppUsesNonExemptEncryption` is false (only standard HTTPS/TLS), so App Store Connect will not ask the export question.

## Play Store, in order
1. Create a Play Console developer account (one-time fee; new personal accounts must run a closed test with 12 testers for 14 days before production).
2. Create the app with package name `com.omni.verbnest`; turn on Play App Signing and upload `apps/verbnest_app/build/app/outputs/bundle/release/app-release.aab` to an internal test track first.
3. Fill the store listing from `docs/release/store-listing.md`, host `privacy-policy.md` at a public URL, answer the data safety form (no data collected, none shared) and the content rating questionnaire.

## App Store, in order
1. Join the Apple Developer Program. In the developer portal register App ID `com.omni.verbnest` and create the app in App Store Connect (iOS and macOS share the id).
2. In Xcode open `apps/verbnest_app/ios/Runner.xcworkspace` and `macos/Runner.xcworkspace`, set your Team under Signing & Capabilities (automatic signing), then `flutter build ipa --release` and upload with Xcode Organizer or `xcrun altool`/Transporter. The macOS Mac App Store build needs the 3rd Party Mac Developer Application and Installer certificates.
3. Fill listing, screenshots, privacy ("Data Not Collected") and review notes from `store-listing.md`.

## Needs the owner
1. Google Play: developer account, `keytool -genkey` upload key, `flutter build appbundle --release`, Play App Signing, data safety form (no data collected), content rating.
2. F-Droid: merge request to `fdroiddata` with a build recipe for the tag; the app has no proprietary dependencies, but check `fjs` (Rust) builds from source in their build server.
3. App Store (iOS and macOS): Apple Developer Program, distribution certificates and profiles, `flutter build ipa`, App Store Connect listing, screenshots, review notes from `store-listing.md`. The `network.server` entitlement is explained in the review notes in `store-listing.md`.
4. Microsoft Store / winget: publisher account, MSIX packaging (`msix` package or Inno Setup), signing certificate, winget manifests with the real installer URL and SHA-256.
5. Flathub: pull request to `flathub/flathub`; replace the placeholder source URL and commit; a Linux machine to build and test the Flatpak.
6. Screenshots, public support URL, hosted privacy policy.
7. Windows and Linux builds have only been compiled in CI, never run by hand.

## Devices
- Android and iOS: phones and tablets only (ADR-018). iOS: `TARGETED_DEVICE_FAMILY = 1,2`, Mac Catalyst, "designed for iPhone/iPad on Mac" and on Vision are off. Android: `uses-feature touchscreen` required, no leanback/watch/automotive/XR. Owner, in Play Console: no extra form factors, exclude Chromebooks in the device catalog. Owner, in App Store Connect: untick the Mac and Vision availability of the iPhone/iPad app.

## Languages
- English only on every platform (ADR-017). Android: `androidResources.localeFilters`; iOS and macOS: `CFBundleLocalizations`; Windows and Linux carry no language resources. In App Store Connect and Play Console keep English as the only localisation.

## Screenshots
- `scripts/screenshots_macos.sh` writes 18 PNGs (2880x1800); `scripts/screenshots_devices.sh` writes the iPhone, iPad and Android sets (portrait and landscape) to `docs/release/screenshots/macos`. Listing copy: `docs/release/app-store-post.md`.

## Mac App Store package
- With Xcode signed in: `xcodebuild archive` then `-exportArchive -allowProvisioningUpdates` using an `app-store-connect` export plist (team NYY6MADXHV, automatic signing) produces a signed `VerbNest.pkg`. Upload it with Transporter.

## Store packages (how a build is made; the last set built was 0.59.5+33)
Use one build number for all three: `n=$(scripts/next_build.sh)`, then pass `--build-name=<VERSION> --build-number=$n` to each build from `apps/verbnest_app`.
- **Android (Play):** `PATH=/usr/local/opt/rustup/bin:$PATH flutter build appbundle --release ...`. With `rustup` on PATH the `fjs` plugin compiles Rust from source; without it the plugin tries precompiled binaries, which do not cover Android, and the build fails with "Requested Rust target is not included in the signed build recipe". Output: `build/app/outputs/bundle/release/app-release.aab`, signed with the upload key from `key.properties` (arm64-v8a, armeabi-v7a, x86_64). About 10 minutes.
- **iOS (App Store):** `flutter build ipa --release ...` (automatic signing, team NYY6MADXHV). Output: `build/ios/ipa/VerbNest.ipa`. Flutter warns that the launch image is the default placeholder.
- **macOS (Mac App Store):** `flutter build macos --release ...`, then in `macos/`: `xcodebuild archive -workspace Runner.xcworkspace -scheme Runner -configuration Release -archivePath VerbNest.xcarchive -allowProvisioningUpdates DEVELOPMENT_TEAM=NYY6MADXHV`, then `xcodebuild -exportArchive -exportOptionsPlist <plist> -allowProvisioningUpdates` with `method=app-store-connect`, `teamID=NYY6MADXHV`, `signingStyle=automatic`, `destination=export`. Output: `VerbNest.pkg`, signed with the 3rd Party Mac Developer Installer certificate; the app inside is universal.
- None of these has been uploaded. Upload the AAB in Play Console, and the IPA and PKG with Transporter.
- **DMG with the same build number:** after `flutter build macos --release --build-number=$n`, run `SKIP_BUILD=1 scripts/package_macos.sh <dir>` so the DMG uses the number in `BUILD_NUMBER` instead of bumping it again.
