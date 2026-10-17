# winget

Package identifier: `Omni.VerbNest`. Publisher: Omni Technical Solutions Pty Ltd. Licence: BSL-1.0 (`distribution/LICENSE_1_0.txt`).

Repositories (moved to the Omni-Technical-Solutions organisation on 2026-10-17): source `https://github.com/Omni-Technical-Solutions/VerbNest` (private), installers `https://github.com/Omni-Technical-Solutions/VerbNest-releases` (public), and the winget fork `https://github.com/Omni-Technical-Solutions/winget-pkgs` (the open PR #451601 now has its branch there). The old `bulhanb/...` addresses redirect, except the source repo.

Installers are hosted publicly on `https://github.com/Omni-Technical-Solutions/VerbNest-releases` (the source repo is private, and winget downloads anonymously). A release asset must never be replaced once a manifest points at it: winget pins its SHA-256.

`manifests/` mirrors the `microsoft/winget-pkgs` layout (`manifests/o/Omni/VerbNest/<version>/`) and keeps a copy of every submitted version.

## New version

1. Bump the app version (`/phase-commit`), then build: `scripts/package_windows.sh`.
2. Create release `v<version>` in `Omni-Technical-Solutions/VerbNest-releases` and upload the setup exe.
3. Submit (needs `wingetcreate`: `winget install Microsoft.WingetCreate`, and a GitHub token with `public_repo`):

   ```sh
   wingetcreate update Omni.VerbNest --version <version> \
     --urls "<installer URL>|x64|user" "<installer URL>|x64|machine" \
     --submit --token <token>
   ```

4. Copy the generated manifests into `manifests/o/Omni/VerbNest/<version>/`.

winget versions are app versions. A rebuild with the same version cannot be resubmitted.
