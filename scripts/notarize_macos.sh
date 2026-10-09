#!/usr/bin/env bash
# Signs VerbNest.app with a Developer ID Application certificate, notarises it
# with Apple and staples the ticket, then builds the DMG. Needs an Apple
# Developer account; never run in CI without secrets set.
#
# A Developer ID Application certificate is required (not yet on this machine;
# only Apple Distribution and Developer ID Installer are installed). Create
# one in the Apple Developer portal, export a .p12, and import into Keychain.
#
# Environment:
#   DEVELOPER_ID   signing identity, e.g. "Developer ID Application: Name (TEAMID)"
#   NOTARY_PROFILE keychain profile made once with
#                  xcrun notarytool store-credentials <name> --apple-id ... --team-id ...
#
# Usage: scripts/notarize_macos.sh [output-dir]
set -euo pipefail

: "${DEVELOPER_ID:?set DEVELOPER_ID}"
: "${NOTARY_PROFILE:?set NOTARY_PROFILE}"

cd "$(git rev-parse --show-toplevel)"
out="${1:-$HOME/Downloads}"

scripts/build.sh macos --release
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
dmg="$out/VerbNest-${version}+${build}-macos-notarized.dmg"
hdiutil create -volname "VerbNest ${version}" -srcfolder "$work/VerbNest.app" -ov -format UDZO "$dmg"
codesign --sign "$DEVELOPER_ID" --timestamp "$dmg"
xcrun notarytool submit "$dmg" --keychain-profile "$NOTARY_PROFILE" --wait
xcrun stapler staple "$dmg"
echo "$dmg"
