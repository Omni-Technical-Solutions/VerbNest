#!/usr/bin/env bash
# Renders store screenshots for iPhone, iPad, Android phone and Android 10"
# tablet. The pixel sizes match the store listings.
#
# Usage: scripts/screenshots_devices.sh [profile...]
#        profiles: iphone ipad android-phone android-tablet iphone-landscape
#                  android-phone-landscape (default: all)
#        Output:   docs/release/screenshots/<profile>/
#
# Same headless harness as scripts/screenshots_macos.sh (see its header), run
# once per device profile in apps/verbnest_app/tool/screenshots_test.dart.
set -euo pipefail

cd "$(git rev-parse --show-toplevel)"
profiles=("$@")
[ ${#profiles[@]} -gt 0 ] || profiles=(iphone ipad android-phone android-tablet iphone-landscape android-phone-landscape)

flutter_bin="$(command -v flutter)"
flutter_root="$(cd "$(dirname "$(readlink "$flutter_bin" || echo "$flutter_bin")")/.." && pwd)"
[ -d "$flutter_root/bin/cache/artifacts/material_fonts" ] || {
  echo "Cannot find Flutter's bundled fonts under $flutter_root" >&2
  exit 1
}

for profile in "${profiles[@]}"; do
  out="docs/release/screenshots/$profile"
  mkdir -p "$out"
  out="$(cd "$out" && pwd)"
  rm -f "$out"/*.png
  (cd apps/verbnest_app &&
    FLUTTER_ROOT="$flutter_root" VERBNEST_SHOTS_PROFILE="$profile" \
      VERBNEST_SHOTS_DIR="$out" flutter test tool/screenshots_test.dart)
  echo "Screenshots in $out:"
  for f in "$out"/*.png; do
    printf '  %s  %s\n' "$(sips -g pixelWidth -g pixelHeight "$f" | awk '/pixel/{printf "%s ", $2}')" "$(basename "$f")"
  done
done
