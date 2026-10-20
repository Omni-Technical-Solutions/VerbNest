#!/usr/bin/env bash
# Signs VerbNest.app with a Developer ID Application certificate, notarises it
# with Apple and staples the ticket, then builds the DMG. Needs an Apple
# Developer account; never run in CI without secrets set.
#
# A Developer ID Application certificate (with its private key) must be in the
# login keychain: create it in the Apple Developer portal from a CSR made on
# this Mac, or import a .p12. Check with
#   security find-identity -v -p codesigning | grep "Developer ID Application"
# (The Developer ID Installer certificate is only for a signed .pkg.)
#
# Environment:
#   DEVELOPER_ID   signing identity, e.g. "Developer ID Application: Name (TEAMID)"
#   NOTARY_PROFILE keychain profile made once with
#                  xcrun notarytool store-credentials <name> --apple-id ... --team-id ...
#                  (an app-specific password, not the Apple ID password)
#   SKIP_BUILD=1   notarise the app already built (keeps the build number of the
#                  store packages) instead of building and bumping it
#
# Usage: scripts/notarize_macos.sh [output-dir]
set -euo pipefail

: "${DEVELOPER_ID:?set DEVELOPER_ID}"
: "${NOTARY_PROFILE:?set NOTARY_PROFILE}"

cd "$(git rev-parse --show-toplevel)"
out="${1:-$HOME/Downloads}"

if [ "${SKIP_BUILD:-}" != "1" ]; then
  scripts/build.sh macos --release
fi
app="apps/verbnest_app/build/macos/Build/Products/Release/VerbNest.app"
[ -d "$app" ] || { echo "Missing $app" >&2; exit 1; }

work="$(mktemp -d)"
trap 'rm -rf "$work"' EXIT
cp -R "$app" "$work/VerbNest.app"

codesign --force --deep --options runtime --timestamp \
  --entitlements apps/verbnest_app/macos/Runner/Release.entitlements \
  --sign "$DEVELOPER_ID" "$work/VerbNest.app"
codesign --verify --deep --strict "$work/VerbNest.app"

ditto -c -k --keepParent "$work/VerbNest.app" "$work/VerbNest.zip"
xcrun notarytool submit "$work/VerbNest.zip" --keychain-profile "$NOTARY_PROFILE" --wait
xcrun stapler staple "$work/VerbNest.app"

version="$(tr -d '[:space:]' < VERSION)"
build="$(tr -d '[:space:]' < BUILD_NUMBER)"
dmg="$out/VerbNest-${version}+${build}-macos-universal.dmg"
# The disk image holds the app and a link to Applications for drag-to-install.
mkdir "$work/dmgsrc"
cp -R "$work/VerbNest.app" "$work/dmgsrc/VerbNest.app"
ln -s /Applications "$work/dmgsrc/Applications"
hdiutil create -volname "VerbNest ${version}" -srcfolder "$work/dmgsrc" -ov -format UDZO "$dmg"
codesign --sign "$DEVELOPER_ID" --timestamp "$dmg"
xcrun notarytool submit "$dmg" --keychain-profile "$NOTARY_PROFILE" --wait
xcrun stapler staple "$dmg"
echo "$dmg"
