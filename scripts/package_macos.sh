#!/usr/bin/env bash
# Builds a release macOS app and packages it as a DMG.
#
# Usage: scripts/package_macos.sh [output-dir]   (default: ~/Downloads)
#
# Goes through scripts/build.sh, so the build number is incremented first.
# The DMG gets a drag-to-Applications layout when `create-dmg` is installed
# (brew install create-dmg) and falls back to a plain `hdiutil` image.
# The app is ad-hoc signed (no Developer ID), so Gatekeeper asks the user to
# approve it on first launch (right-click > Open). Notarised builds need a
# Developer ID certificate and are a separate, manual step.
set -euo pipefail

cd "$(git rev-parse --show-toplevel)"
out="${1:-$HOME/Downloads}"

scripts/build.sh macos --release

version="$(tr -d '[:space:]' < VERSION)"
build="$(tr -d '[:space:]' < BUILD_NUMBER)"
app="apps/verbnest_app/build/macos/Build/Products/Release/Verbnest.app"
icon="apps/verbnest_app/macos/Runner/Assets.xcassets/AppIcon.appiconset/app_icon_512.png"
[ -d "$app" ] || { echo "Missing $app" >&2; exit 1; }

arch="$(uname -m)"
name="Verbnest-${version}+${build}-macos-${arch}.dmg"
stage="$(mktemp -d)"
work="$(mktemp -d)"
trap 'rm -rf "$stage" "$work"' EXIT

cp -R "$app" "$stage/Verbnest.app"
codesign --force --deep --sign - "$stage/Verbnest.app"

if command -v create-dmg >/dev/null; then
  create-dmg \
    --volname "Verbnest ${version}" \
    --volicon "$icon" \
    --window-pos 200 120 --window-size 600 400 \
    --icon-size 100 \
    --icon "Verbnest.app" 175 190 \
    --hide-extension "Verbnest.app" \
    --app-drop-link 425 190 \
    "$work/$name" "$stage/" >/dev/null
else
  ln -s /Applications "$stage/Applications"
  hdiutil create -volname "Verbnest ${version}" -srcfolder "$stage" \
    -ov -format UDZO "$work/$name" >/dev/null
fi

mkdir -p "$out"
mv -f "$work/$name" "$out/$name"
echo "$out/$name"
