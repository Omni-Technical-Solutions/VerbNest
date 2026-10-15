# Linux build (.deb)

Release `.deb` files are built against Ubuntu 22.04 (glibc 2.35, GTK 3.24.33,
libsecret 0.20.5), the oldest Ubuntu LTS in standard support, so they also
install on 24.04+ and Debian 12+/13. A build on a newer host links newer glibc
symbols and fails on older systems, so always build in the 22.04 root.

## One-time setup (no root needed)

1. Unpack `ubuntu-base-22.04.x-base-amd64.tar.gz` (cdimage.ubuntu.com) into
   `~/jammy` and copy `/etc/resolv.conf` into `~/jammy/etc/`.
2. Run commands in it with `bwrap --unshare-user --uid 0 --gid 0 --bind ~/jammy /
   --dev /dev --proc /proc --bind /tmp /tmp --bind $HOME /home/<user>` and
   `HOME`, `CARGO_HOME`, `RUSTUP_HOME`, `PATH` (flutter and cargo bins) set to
   the host's home paths.
3. Inside: `apt-get -o APT::Sandbox::User=root install --no-install-recommends
   clang cmake ninja-build pkg-config libgtk-3-dev libsecret-1-dev liblzma-dev
   git curl unzip xz-utils zip ca-certificates`. dpkg reports a chown error
   (only one uid is mapped); the tools still work.
4. Rust via rustup under the host home (the `fjs` plugin compiles Rust).
   Flutter SDK from the host (`~/snap/flutter/common/flutter`; the snap
   launcher is blocked, call the SDK directly).

## Build

Inside the 22.04 root, in the repo: `rm -rf apps/verbnest_app/build/linux`
(a cache from another distro breaks the install step), then
`scripts/package_linux.sh` (outside the root, `SKIP_BUILD=1` packages the
bundle already built). The libc6 dependency is taken from the bundle.
