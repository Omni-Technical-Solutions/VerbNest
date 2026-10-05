#!/usr/bin/env bash
# Signs PostIt.app with a Developer ID certificate, notarises it with Apple and
# staples the ticket, then builds the DMG. Needs an Apple Developer account;
# never run in CI without secrets set. Not tested: there is no Developer ID on
# the development machine.
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
app="apps/postit_app/build/macos/Build/Products/Release/PostIt.app"
[ -d "$app" ] || { echo "Missing $app" >&2; exit 1; }

work="$(mktemp -d)"
trap 'rm -rf "$work"' EXIT
cp -R "$app" "$work/PostIt.app"

codesign --force --deep --options runtime --timestamp \
  --entitlements apps/postit_app/macos/Runner/Release.entitlements \
  --sign "$DEVELOPER_ID" "$work/PostIt.app"
codesign --verify --deep --strict "$work/PostIt.app"

ditto -c -k --keepParent "$work/PostIt.app" "$work/PostIt.zip"
xcrun notarytool submit "$work/PostIt.zip" --keychain-profile "$NOTARY_PROFILE" --wait
xcrun stapler staple "$work/PostIt.app"

version="$(tr -d '[:space:]' < VERSION)"
build="$(tr -d '[:space:]' < BUILD_NUMBER)"
dmg="$out/PostIt-${version}+${build}-macos-notarized.dmg"
hdiutil create -volname "PostIt ${version}" -srcfolder "$work/PostIt.app" -ov -format UDZO "$dmg"
codesign --sign "$DEVELOPER_ID" --timestamp "$dmg"
xcrun notarytool submit "$dmg" --keychain-profile "$NOTARY_PROFILE" --wait
xcrun stapler staple "$dmg"
echo "$dmg"
