#!/usr/bin/env bash
# Builds a release macOS app and packages it as a DMG.
#
# Usage: scripts/package_macos.sh [output-dir]   (default: ~/Downloads)
#
# Goes through scripts/build.sh, so the build number is incremented first.
# The DMG gets a drag-to-Applications layout when `create-dmg` is installed
# (brew install create-dmg) and falls back to a plain `hdiutil` image.
#
# The app is signed with an Apple certificate (hardened runtime, timestamp,
# entitlements). The identity defaults to the Apple Distribution certificate;
# override with SIGN_IDENTITY for a Developer ID Application cert (needed for
# notarisation). Notarised builds are a separate, manual step
# (scripts/notarize_macos.sh).
set -euo pipefail

cd "$(git rev-parse --show-toplevel)"
out="${1:-$HOME/Downloads}"

# Signing identity: Apple Distribution by default; override with SIGN_IDENTITY.
SIGN_IDENTITY="${SIGN_IDENTITY:-Apple Distribution: Omni Technical Solutions Pty Ltd (NYY6MADXHV)}"
ENTITLEMENTS="apps/verbnest_app/macos/Runner/Release.entitlements"

scripts/build.sh macos --release

version="$(tr -d '[:space:]' < VERSION)"
build="$(tr -d '[:space:]' < BUILD_NUMBER)"
app="apps/verbnest_app/build/macos/Build/Products/Release/VerbNest.app"
icon="apps/verbnest_app/macos/Runner/Assets.xcassets/AppIcon.appiconset/app_icon_512.png"
[ -d "$app" ] || { echo "Missing $app" >&2; exit 1; }

arch="$(uname -m)"
name="VerbNest-${version}+${build}-macos-${arch}.dmg"
stage="$(mktemp -d)"
work="$(mktemp -d)"
trap 'rm -rf "$stage" "$work"' EXIT

cp -R "$app" "$stage/VerbNest.app"
codesign --force --deep --options runtime --timestamp \
  --entitlements "$ENTITLEMENTS" \
  --sign "$SIGN_IDENTITY" "$stage/VerbNest.app"
codesign --verify --deep --strict "$stage/VerbNest.app"
echo "Signed with: $SIGN_IDENTITY"

if command -v create-dmg >/dev/null; then
  create-dmg \
    --volname "VerbNest ${version}" \
    --volicon "$icon" \
    --window-pos 200 120 --window-size 600 400 \
    --icon-size 100 \
    --icon "VerbNest.app" 175 190 \
    --hide-extension "VerbNest.app" \
    --app-drop-link 425 190 \
    "$work/$name" "$stage/" >/dev/null
else
  ln -s /Applications "$stage/Applications"
  hdiutil create -volname "VerbNest ${version}" -srcfolder "$stage" \
    -ov -format UDZO "$work/$name" >/dev/null
fi

mkdir -p "$out"
mv -f "$work/$name" "$out/$name"
echo "$out/$name"
