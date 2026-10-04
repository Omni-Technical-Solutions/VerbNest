#!/usr/bin/env bash
# Increments the build number. Run before every build; the number only ever
# goes up, across all versions and platforms.
#
# BUILD_NUMBER is the source of truth; the `+N` in apps/postit_app/pubspec.yaml
# is kept in sync with it.
#
# Usage: scripts/next_build.sh        (prints the new build number)
set -euo pipefail

cd "$(git rev-parse --show-toplevel)"

app=apps/postit_app/pubspec.yaml
current="$(tr -d '[:space:]' < BUILD_NUMBER)"
next="$((current + 1))"
version="$(tr -d '[:space:]' < VERSION)"

echo "$next" > BUILD_NUMBER
sed -i.bak -E "s/^version: .*/version: ${version}+${next}/" "$app"
rm -f "$app.bak"

echo "$next"
