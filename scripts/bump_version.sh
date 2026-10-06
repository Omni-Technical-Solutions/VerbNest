#!/usr/bin/env bash
# Bumps the single repo version (VERSION file) and every workspace pubspec.
#
#   feature -> major   (X+1.0.0)
#   minor   -> minor   (x.Y+1.0)
#   fix     -> patch   (x.y.Z+1)
#   chore   -> version unchanged
#
# The build number is separate: it only goes up when a build is made
# (scripts/next_build.sh, scripts/build.sh) and is never reset or lowered by a
# version bump.
#
# Usage: scripts/bump_version.sh <feature|minor|fix|chore> [--dry-run]
# Prints `<version>+<build>` on stdout.
set -euo pipefail

type="${1:?usage: bump_version.sh <feature|minor|fix|chore> [--dry-run]}"
dry="${2:-}"
cd "$(git rev-parse --show-toplevel)"

app=apps/verbnest_app/pubspec.yaml
current="$(tr -d '[:space:]' < VERSION)"
build="$(tr -d '[:space:]' < BUILD_NUMBER)"
IFS=. read -r major minor patch <<<"$current"

case "$type" in
  feature) next="$((major + 1)).0.0" ;;
  minor)   next="${major}.$((minor + 1)).0" ;;
  fix)     next="${major}.${minor}.$((patch + 1))" ;;
  chore)   next="$current" ;;
  *) echo "unknown type: $type" >&2; exit 2 ;;
esac

if [ "$dry" = "--dry-run" ]; then echo "${next}+${build}"; exit 0; fi

echo "$next" > VERSION

for f in packages/*/pubspec.yaml test_server/pubspec.yaml; do
  [ -f "$f" ] || continue
  sed -i.bak -E "s/^version: .*/version: ${next}/" "$f"
  rm -f "$f.bak"
done

sed -i.bak -E "s/^version: .*/version: ${next}+${build}/" "$app"
rm -f "$app.bak"

echo "${next}+${build}"
