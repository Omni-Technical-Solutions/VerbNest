#!/usr/bin/env bash
# Signs Verbnest.app with a Developer ID Application certificate, notarises it
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
app="apps/verbnest_app/build/macos/Build/Products/Release/Verbnest.app"
[ -d "$app" ] || { echo "Missing $app" >&2; exit 1; }

work="$(mktemp -d)"
trap 'rm -rf "$work"' EXIT
cp -R "$app" "$work/Verbnest.app"

codesign --force --deep --options runtime --timestamp \
  --entitlements apps/verbnest_app/macos/Runner/Release.entitlements \
  --sign "$DEVELOPER_ID" "$work/Verbnest.app"
codesign --verify --deep --strict "$work/Verbnest.app"

ditto -c -k --keepParent "$work/Verbnest.app" "$work/Verbnest.zip"
xcrun notarytool submit "$work/Verbnest.zip" --keychain-profile "$NOTARY_PROFILE" --wait
xcrun stapler staple "$work/Verbnest.app"

version="$(tr -d '[:space:]' < VERSION)"
build="$(tr -d '[:space:]' < BUILD_NUMBER)"
dmg="$out/Verbnest-${version}+${build}-macos-notarized.dmg"
hdiutil create -volname "Verbnest ${version}" -srcfolder "$work/Verbnest.app" -ov -format UDZO "$dmg"
codesign --sign "$DEVELOPER_ID" --timestamp "$dmg"
xcrun notarytool submit "$dmg" --keychain-profile "$NOTARY_PROFILE" --wait
xcrun stapler staple "$dmg"
echo "$dmg"
