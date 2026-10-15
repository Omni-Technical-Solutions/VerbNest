#!/usr/bin/env bash
# Builds a release Linux app and packages it as a standalone .deb (amd64).
#
# Usage: scripts/package_linux.sh [output-dir]   (default: ~/Downloads)
#
# Goes through scripts/build.sh, so the build number is incremented first
# (unless SKIP_BUILD=1, which packages the bundle already built and takes the
# build number from BUILD_NUMBER).
#
# Needs flutter, a Rust toolchain (the fjs plugin compiles Rust), cmake, ninja,
# clang, libgtk-3-dev, libsecret-1-dev and dpkg-deb. Built on Ubuntu 24.04, so
# the package needs glibc >= 2.39 (Ubuntu 24.04+, Debian 13+).
#
# Layout: the Flutter bundle lives in /opt/verbnest, /usr/bin/verbnest links to
# it, plus a desktop entry and icon. The bundle is self-contained apart from
# the system GTK and libsecret libraries (declared as dependencies).
set -euo pipefail

cd "$(git rev-parse --show-toplevel)"
out="${1:-$HOME/Downloads}"

if [[ "${SKIP_BUILD:-0}" != "1" ]]; then
  scripts/build.sh linux --release
fi

name="$(tr -d '[:space:]' < VERSION)"
number="$(tr -d '[:space:]' < BUILD_NUMBER)"
bundle="apps/verbnest_app/build/linux/x64/release/bundle"
[[ -x "$bundle/verbnest_app" ]] || { echo "No bundle at $bundle" >&2; exit 1; }

stage="$(mktemp -d)"
trap 'rm -rf "$stage"' EXIT
root="$stage/pkg"

install -d "$root/opt/verbnest" "$root/usr/bin" "$root/DEBIAN" \
  "$root/usr/share/applications" "$root/usr/share/icons/hicolor/512x512/apps" \
  "$root/usr/share/doc/verbnest"
cp -a "$bundle/." "$root/opt/verbnest/"
ln -s /opt/verbnest/verbnest_app "$root/usr/bin/verbnest"
install -m 644 assets/icon/verbnest_icon_512.png \
  "$root/usr/share/icons/hicolor/512x512/apps/verbnest.png"
cat > "$root/usr/share/applications/com.omni.verbnest.desktop" <<DESKTOP
[Desktop Entry]
Type=Application
Name=VerbNest
Comment=Local-first API client
Exec=verbnest
Icon=verbnest
Categories=Development;Network;
Terminal=false
StartupWMClass=com.omni.verbnest
DESKTOP
cp CHANGELOG.md "$root/usr/share/doc/verbnest/changelog"
gzip -9n "$root/usr/share/doc/verbnest/changelog"

size="$(du -sk "$root" | cut -f1)"
cat > "$root/DEBIAN/control" <<CONTROL
Package: verbnest
Version: ${name}+${number}
Section: devel
Priority: optional
Architecture: amd64
Maintainer: Omni Technical Solutions <info@omnits.pro>
Installed-Size: ${size}
Depends: libc6 (>= 2.39), libstdc++6, libgtk-3-0t64 | libgtk-3-0, libsecret-1-0
Description: Local-first API client
 VerbNest is a local-first API client for building, sending and testing
 HTTP requests. Workspaces and history stay on your machine.
CONTROL

find "$root" -type d -exec chmod 755 {} +
mkdir -p "$out"
deb="$out/verbnest_${name}+${number}_amd64.deb"
fakeroot dpkg-deb --root-owner-group --build "$root" "$deb" >/dev/null
echo "Wrote $deb"
