#!/usr/bin/env bash
# Increments the build number. Run before every build; the number only ever
# goes up, across all versions and platforms.
#
# BUILD_NUMBER is the source of truth; the `+N` in apps/verbnest_app/pubspec.yaml
# is kept in sync with it.
#
# Usage: scripts/next_build.sh        (prints the new build number)
set -euo pipefail

cd "$(git rev-parse --show-toplevel)"

app=apps/verbnest_app/pubspec.yaml
current="$(tr -d '[:space:]' < BUILD_NUMBER)"
# Another machine may have taken numbers already (build 70 was used twice):
# start from the highest of this checkout and origin/main. Offline, or with no
# remote, the local number is used and a warning says so.
if git fetch --quiet origin main 2>/dev/null; then
  remote="$(git show origin/main:BUILD_NUMBER 2>/dev/null | tr -d '[:space:]' || true)"
  if [ -n "$remote" ] && [ "$remote" -gt "$current" ] 2>/dev/null; then
    echo "next_build: origin/main is at build $remote, this checkout at $current; using $remote" >&2
    current="$remote"
  fi
else
  echo "next_build: could not reach origin; the build number is only checked against this checkout" >&2
fi
next="$((current + 1))"
version="$(tr -d '[:space:]' < VERSION)"

echo "$next" > BUILD_NUMBER
sed -i.bak -E "s/^version: .*/version: ${version}+${next}/" "$app"
rm -f "$app.bak"

echo "$next"
