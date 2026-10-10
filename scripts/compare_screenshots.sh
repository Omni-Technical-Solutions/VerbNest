#!/usr/bin/env bash
# Renders store screenshots into a scratch folder and lists the ones that differ
# from the committed set, so a UI change shows which store images to review.
#
# Usage: scripts/compare_screenshots.sh [profile...]
#        profiles: macos iphone ipad android-phone android-tablet (default: all)
#
# Nothing in docs/release/screenshots is overwritten. Exit code 1 when any
# screenshot changed. To accept the changes run scripts/screenshots_macos.sh
# or scripts/screenshots_devices.sh and commit the result.
set -euo pipefail

cd "$(git rev-parse --show-toplevel)"
profiles=("$@")
[ ${#profiles[@]} -gt 0 ] || profiles=(macos iphone ipad android-phone android-tablet)

flutter_bin="$(command -v flutter)"
flutter_root="$(cd "$(dirname "$(readlink "$flutter_bin" || echo "$flutter_bin")")/.." && pwd)"
scratch="$(mktemp -d)"
trap 'rm -rf "$scratch"' EXIT

status=0
for profile in "${profiles[@]}"; do
  out="$scratch/$profile"
  mkdir -p "$out"
  echo "== $profile"
  (cd apps/verbnest_app &&
    FLUTTER_ROOT="$flutter_root" VERBNEST_SHOTS_PROFILE="$profile" \
      VERBNEST_SHOTS_DIR="$out" flutter test tool/screenshots_test.dart >/dev/null)
  (cd apps/verbnest_app &&
    dart run tool/compare_screenshots.dart \
      "../../docs/release/screenshots/$profile" "$out") || status=1
done
exit $status
