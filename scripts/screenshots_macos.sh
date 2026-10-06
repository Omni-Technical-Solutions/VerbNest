#!/usr/bin/env bash
# Renders the app screens as 2880 x 1800 PNG files for the Mac App Store.
#
# Usage: scripts/screenshots_macos.sh [output-dir]
#        (default: docs/release/screenshots/macos)
#
# The app runs headless inside `flutter test` (apps/verbnest_app/tool/
# screenshots_test.dart) with a demo workspace and canned responses, so it
# needs no window, no screen-recording permission and no network. Fonts come
# from the Flutter SDK (Roboto) and macOS (SF Mono, Geeza Pro).
#
# 2880 x 1800 is one of the sizes the Mac App Store accepts (16:10); the
# others (2560 x 1600, 1440 x 900, 1280 x 800) can be made from these with
# `sips -z <height> <width> in.png --out out.png`.
set -euo pipefail

cd "$(git rev-parse --show-toplevel)"
out="${1:-docs/release/screenshots/macos}"
mkdir -p "$out"
out="$(cd "$out" && pwd)"

flutter_bin="$(command -v flutter)"
flutter_root="$(cd "$(dirname "$(readlink "$flutter_bin" || echo "$flutter_bin")")/.." && pwd)"
[ -d "$flutter_root/bin/cache/artifacts/material_fonts" ] || {
  echo "Cannot find Flutter's bundled fonts under $flutter_root" >&2
  exit 1
}

rm -f "$out"/*.png
cd apps/verbnest_app
FLUTTER_ROOT="$flutter_root" VERBNEST_SHOTS_DIR="$out" \
  flutter test tool/screenshots_test.dart

echo
echo "Screenshots in $out:"
for f in "$out"/*.png; do
  printf '  %s  %s\n' "$(sips -g pixelWidth -g pixelHeight "$f" | awk '/pixel/{printf "%s ", $2}')" "$(basename "$f")"
done
