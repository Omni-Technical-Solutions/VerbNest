#!/usr/bin/env bash
# Builds a release Windows app and packages it as an Inno Setup installer.
#
# Usage: scripts/package_windows.sh [output-dir]   (default: ~/Downloads)
#
# Run from Git Bash on Windows. Goes through scripts/build.sh, so the build
# number is incremented first (unless SKIP_BUILD=1, which packages the app
# already built with the number in BUILD_NUMBER).
# Needs Inno Setup 6 (winget install JRSoftware.InnoSetup); set ISCC to the
# compiler path if it is not in a standard location.
#
# Code signing (app exe and DLLs, setup, uninstaller), first match wins:
#   SIGN_METADATA     Azure Artifact Signing metadata.json; defaults to
#                     ~/.verbnest-signing/metadata.json when that exists.
#                     Needs the Artifact Signing client tools
#                     (winget install Microsoft.Azure.ArtifactSigningClientTools)
#                     and an Azure sign-in (az login). See
#                     docs/release/windows-signing.md.
#   SIGN_THUMBPRINT   SHA-1 thumbprint of a code-signing certificate in the
#                     current user's certificate store (OV/EV cert, token).
# Neither set: the installer is built unsigned, with a warning.
# REQUIRE_SIGNING=1 fails instead of building unsigned.
# SIGNTOOL and SIGN_DLIB override the tool locations.
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

# Signing set-up. sign_args are the signtool arguments after `sign`, as
# Windows strings; Git Bash must not rewrite their `/x` switches as paths.
export MSYS_NO_PATHCONV=1 MSYS2_ARG_CONV_EXCL='*'
SIGN_METADATA="${SIGN_METADATA:-}"
if [ -z "$SIGN_METADATA" ] && [ -f "$HOME/.verbnest-signing/metadata.json" ]; then
  SIGN_METADATA="$HOME/.verbnest-signing/metadata.json"
fi
sign_args=()
if [ -n "$SIGN_METADATA" ] || [ -n "${SIGN_THUMBPRINT:-}" ]; then
  if [ -z "${SIGNTOOL:-}" ]; then
    # Artifact Signing needs signtool from Windows SDK 10.0.22621.755 or later.
    SIGNTOOL="$(ls -d "/c/Program Files (x86)/Windows Kits/10/bin/"10.0.*/x64/signtool.exe 2>/dev/null | sort -V | tail -n 1)"
  fi
  [ -f "${SIGNTOOL:-}" ] || { echo "signtool.exe not found; set SIGNTOOL" >&2; exit 1; }
  sign_args=(/fd SHA256 /tr http://timestamp.acs.microsoft.com /td SHA256)
  if [ -n "$SIGN_METADATA" ]; then
    SIGN_DLIB="${SIGN_DLIB:-${LOCALAPPDATA:-}/Microsoft/MicrosoftArtifactSigningClientTools/Azure.CodeSigning.Dlib.dll}"
    [ -f "$SIGN_DLIB" ] || { echo "Artifact Signing dlib not found: $SIGN_DLIB" >&2; exit 1; }
    [ -f "$SIGN_METADATA" ] || { echo "Missing $SIGN_METADATA" >&2; exit 1; }
    sign_args+=(/dlib "$(cygpath -w "$SIGN_DLIB")" /dmdf "$(cygpath -w "$SIGN_METADATA")")
    echo "Signing with Artifact Signing ($SIGN_METADATA)"
  else
    sign_args+=(/s My /sha1 "$SIGN_THUMBPRINT")
    echo "Signing with certificate $SIGN_THUMBPRINT"
  fi
elif [ "${REQUIRE_SIGNING:-}" = "1" ]; then
  echo "REQUIRE_SIGNING=1 but no signing is configured" >&2; exit 1
else
  echo "Warning: no signing configured; the installer will be unsigned" >&2
fi

if [ "${SKIP_BUILD:-}" != "1" ]; then
  scripts/build.sh windows --release
fi

version="$(tr -d '[:space:]' < VERSION)"
build="$(tr -d '[:space:]' < BUILD_NUMBER)"
release="apps/verbnest_app/build/windows/x64/runner/Release"
[ -f "$release/verbnest_app.exe" ] || { echo "Missing $release/verbnest_app.exe" >&2; exit 1; }

iscc_sign=()
if [ ${#sign_args[@]} -gt 0 ]; then
  # Sign the app and every bundled DLL before they go into the installer.
  mapfile -t binaries < <(find "$release" -maxdepth 1 \( -name '*.exe' -o -name '*.dll' \))
  win_binaries=()
  for b in "${binaries[@]}"; do win_binaries+=("$(cygpath -w "$b")"); done
  "$SIGNTOOL" sign "${sign_args[@]}" "${win_binaries[@]}"
  # Inno Setup signs the setup and the uninstaller with the same command;
  # it replaces $f with the quoted file name and $q with a quote. Literal
  # quotes would reach ISCC as \" (Git Bash escaping) and break its parsing.
  cmd="\$q$(cygpath -w "$SIGNTOOL")\$q sign"
  for a in "${sign_args[@]}"; do
    case "$a" in *' '*) cmd+=" \$q$a\$q" ;; *) cmd+=" $a" ;; esac
  done
  iscc_sign=("-Ssigntool=$cmd \$f" "-DSign=1")
fi

name="VerbNest-${version}+${build}-windows-x64-setup"
mkdir -p "$out"
"$ISCC" -Q "${iscc_sign[@]}" \
  "-DAppVersion=${version}" "-DBuildNumber=${build}" \
  "-DSourceDir=$(cygpath -w "$PWD/$release")" \
  "-DOutputDir=$(cygpath -w "$out")" "-DOutputName=${name}" \
  "$(cygpath -w distribution/windows/verbnest.iss)"

if [ ${#sign_args[@]} -gt 0 ]; then
  "$SIGNTOOL" verify /pa "$(cygpath -w "$out/$name.exe")" >/dev/null
  echo "Signed and verified"
fi
echo "$out/$name.exe"
