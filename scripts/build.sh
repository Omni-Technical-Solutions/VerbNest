#!/usr/bin/env bash
# Builds the Flutter app with a fresh, higher build number.
#
# Usage: scripts/build.sh <flutter build target and flags...>
#   e.g. scripts/build.sh macos --release
#        scripts/build.sh apk --debug
#
# The build number is incremented before the build starts, so a failed build
# still consumes its number. Numbers are never reused.
set -euo pipefail

cd "$(git rev-parse --show-toplevel)"

number="$(scripts/next_build.sh)"
name="$(tr -d '[:space:]' < VERSION)"
echo "Building PostIt ${name}+${number}"

cd apps/postit_app
exec flutter build "$@" --build-name="$name" --build-number="$number"
