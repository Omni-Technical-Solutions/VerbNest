# Store release checklist

What is ready in the repository and what only the account owner can do. Nothing here has been run against a real store.

## Ready
- App id `org.postit.postit_app` (Android, Linux), bundle id `org.postit.postitApp` (Apple). Change them first if the owner wants another domain; stores fix the id for good.
- Version and build number come from `VERSION` and `BUILD_NUMBER`; build with `scripts/build.sh`.
- Android release signing reads `apps/postit_app/android/key.properties` (`storeFile`, `storePassword`, `keyAlias`, `keyPassword`); without it the release is debug-signed.
- F-Droid / Play text and changelog layout: `distribution/fastlane/metadata/android/en-US/`.
- Flathub draft: `distribution/flatpak/` (manifest, metainfo, desktop file).
- winget templates: `distribution/winget/`.
- macOS: `scripts/package_macos.sh` (ad-hoc DMG) and `scripts/notarize_macos.sh` (Developer ID signing, notarisation, stapling).
- Listing text, review notes, privacy policy draft: `docs/release/`.

## Needs the owner
1. Google Play: developer account, `keytool -genkey` upload key, `flutter build appbundle --release`, Play App Signing, data safety form (no data collected), content rating.
2. F-Droid: merge request to `fdroiddata` with a build recipe for the tag; the app has no proprietary dependencies, but check `fjs` (Rust) builds from source in their build server.
3. App Store (iOS and macOS): Apple Developer Program, distribution certificates and profiles, `flutter build ipa`, App Store Connect listing, screenshots, review notes from `store-listing.md`. Sandbox entitlements for outgoing network and user-selected files need review.
4. Microsoft Store / winget: publisher account, MSIX packaging (`msix` package or Inno Setup), signing certificate, winget manifests with the real installer URL and SHA-256.
5. Flathub: pull request to `flathub/flathub`; replace the placeholder source URL and commit; a Linux machine to build and test the Flatpak.
6. Screenshots, public support URL, hosted privacy policy.
7. Windows and Linux builds have only been compiled in CI, never run by hand.
