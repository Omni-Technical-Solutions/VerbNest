# Plan: publish VerbNest to winget as `Omni.VerbNest`

Goal: `winget install Omni.VerbNest` installs the current Windows build, and each later release reaches winget with one command.

Status (2026-10-13): submitted, waiting for winget validation and moderator review in [microsoft/winget-pkgs#451601](https://github.com/microsoft/winget-pkgs/pull/451601).

## Decisions (owner, 2026-10-13)

| # | Question | Decision |
| --- | --- | --- |
| B1 | Where to host installers (winget downloads anonymously; the source repo is private) | Public installer-only repo [`bulhanb/verbnest-releases`](https://github.com/bulhanb/verbnest-releases) |
| B2 | Licence | Boost Software License 1.0 (`BSL-1.0`), confirmed as Boost, not Business Source. Text: `distribution/LICENSE_1_0.txt`, shown and installed by the installer, `LICENSE` in the releases repo |
| B3 | Publisher name | Omni Technical Solutions Pty Ltd: installer `AppPublisher`, exe `CompanyName`, manifest `Publisher` |
| — | Account for the winget PR | `bulhanb` (fork `bulhanb/winget-pkgs`, created by `wingetcreate`) |

Code signing is still not done. Winget accepts unsigned installers; signing (Azure Trusted Signing or an OV certificate) stays a later step.

## Steps

### 1. Prepare the installer ✅

- ✅ `AppPublisher`, `AppCopyright`, publisher/support URLs and `LicenseFile` in `distribution/windows/verbnest.iss`; `CompanyName` and `LegalCopyright` in `apps/verbnest_app/windows/runner/Runner.rc`. Rebuilt as `0.59.3+25`.
- ✅ Install test on the development machine (not a clean sandbox: Windows Sandbox and local manifest installs need admin). Silent per-user install over the existing build 24 (an upgrade): exit 0, one Apps & Features entry `VerbNest` / `0.59.3` / `Omni Technical Solutions Pty Ltd`, Start menu shortcut, `LICENSE_1_0.txt` installed, exe version info shows the new company and copyright, app launches with its window. Reinstall: exit 0, still one entry. Silent uninstall: exit 0, entry, exe and Start menu folder removed. Build 25 reinstalled afterwards.
- Not tested: machine scope (`/ALLUSERS`, needs elevation); a clean machine.

### 2. Host the installer publicly ✅

- ✅ Repo `bulhanb/verbnest-releases` with README and LICENSE.
- ✅ Release [`v0.59.3`](https://github.com/bulhanb/verbnest-releases/releases/tag/v0.59.3) with `VerbNest-0.59.3+25-windows-x64-setup.exe`, SHA-256 `514D2D2788149CCC3BC5313660E044774A4613EB247336AD26830931310C2F21`. An anonymous download returns the same hash. Never replace this asset.

### 3. Manifests ✅

- ✅ `distribution/winget/manifests/o/Omni/VerbNest/0.59.3/` (version, installer, defaultLocale; schema 1.10.0). Inno installer, user scope (`/CURRENTUSER`) and machine scope (`/ALLUSERS`, `elevatesSelf`), product code `{4831FE71-9D3A-4C42-B468-657CE7AA76F2}_is1`, minimum Windows 10. Description taken from the approved App Store copy.
- ✅ `winget validate` passes.
- Not done: `winget install --manifest` (needs the admin setting `LocalManifestFiles`). Winget's validation pipeline runs the equivalent.

### 4. Submit ⏳

- ✅ `wingetcreate submit` opened [#451601](https://github.com/microsoft/winget-pkgs/pull/451601).
- ⏳ Sign the Microsoft CLA if the bot asks on the PR (owner, once per account).
- ⏳ Watch the PR: automated validation (install in a VM, Defender scan, URL checks), then moderator review. Answer labels such as `Needs-Author-Feedback`. The package is installable once the PR merges.

### 5. Later releases ✅ (documented)

- ✅ `distribution/winget/README.md` has the update steps (`wingetcreate update ... --submit`); roadmap rule 7 points to it.
- Winget versions are app versions. A rebuild with the same version cannot be resubmitted.

## Risks

- Defender or SmartScreen flags the unsigned build during validation. Mitigation: reply on the PR; add signing.
- Machine scope is untested; if validation fails on it, drop the machine installer entry and resubmit.
