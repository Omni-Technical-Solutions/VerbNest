#!/usr/bin/env bash
# Builds a release Windows app and packages it as an Inno Setup installer.
#
# Usage: scripts/package_windows.sh [output-dir]   (default: ~/Downloads)
#
# Run from Git Bash on Windows. Goes through scripts/build.sh, so the build
# number is incremented first (unless SKIP_BUILD=1, which packages the app
# already built with the number in BUILD_NUMBER).
# Needs Inno Setup 6 (winget install JRSoftware.InnoSetup); set ISCC to the
# compiler path if it is not in a standard location. The installer is not
# code-signed.
set -euo pipefail

cd "$(git rev-parse --show-toplevel)"
out="${1:-$HOME/Downloads}"

if [ -z "${ISCC:-}" ]; then
  for candidate in \
    "${LOCALAPPDATA:-}/Programs/Inno Setup 6/ISCC.exe" \
    "/c/Program Files (x86)/Inno Setup 6/ISCC.exe" \
    "/c/Program Files/Inno Setup 6/ISCC.exe"; do
    if [ -f "$candidate" ]; then ISCC="$candidate"; break; fi
  done
fi
[ -n "${ISCC:-}" ] || { echo "Inno Setup compiler (ISCC.exe) not found; set ISCC" >&2; exit 1; }

if [ "${SKIP_BUILD:-}" != "1" ]; then
  scripts/build.sh windows --release
fi

version="$(tr -d '[:space:]' < VERSION)"
build="$(tr -d '[:space:]' < BUILD_NUMBER)"
release="apps/verbnest_app/build/windows/x64/runner/Release"
[ -f "$release/verbnest_app.exe" ] || { echo "Missing $release/verbnest_app.exe" >&2; exit 1; }

name="VerbNest-${version}+${build}-windows-x64-setup"
mkdir -p "$out"
# `-` switches, not `/`: Git Bash rewrites `/D...` arguments as paths.
"$ISCC" -Q \
  "-DAppVersion=${version}" "-DBuildNumber=${build}" \
  "-DSourceDir=$(cygpath -w "$PWD/$release")" \
  "-DOutputDir=$(cygpath -w "$out")" "-DOutputName=${name}" \
  "$(cygpath -w distribution/windows/verbnest.iss)"
echo "$out/$name.exe"
