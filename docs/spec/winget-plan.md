# Plan: publish VerbNest to winget as `Omni.VerbNest`

Goal: `winget install Omni.VerbNest` installs the current Windows build, and each later release reaches winget with one command.

Current state (2026-10-13):

- Installer: `VerbNest-0.59.3+24-windows-x64-setup.exe` (Inno Setup 6, x64, 20 MB), built by `scripts/package_windows.sh` from `distribution/windows/verbnest.iss`. Not code-signed. Installed and uninstalled by hand: never.
- Hosted on GitHub release v0.59.3 of `bulhanb/verbnest`, which is a **private** repo.
- Nothing named `Omni.*` or VerbNest exists in winget yet (checked with `winget search`), so the identifier is free.
- `distribution/winget/README.md` still names the identifier `com.omni.verbnest`. Winget uses `Publisher.Package`, so it becomes `Omni.VerbNest`.

## Blockers

| # | Blocker | Why it matters | Recommendation |
| --- | --- | --- | --- |
| B1 | Installer URL is in a private repo | Winget clients and the validation pipeline download `InstallerUrl` without signing in; private release assets return 404. | Create a public, installer-only repo `bulhanb/verbnest-releases` and upload the Windows installers there. The source stays private. Alternatives: make `verbnest` public, or host on a VerbNest website. |
| B2 | Licence field | `License` is required in the locale manifest. The repo has no LICENSE file. | `License: Proprietary`. Add `LicenseUrl` once the terms are hosted publicly (optional for the first submission). |
| B3 | Publisher name | Winget matches installed apps by Apps & Features data. The installer writes `Publisher=Omni`. The Apple certificate uses "Omni Technical Solutions Pty Ltd". | Decide before the first submission and use the same value in the `.iss` and the manifest. Recommended: legal name in both. Only the installer changes, so `SKIP_BUILD=1 scripts/package_windows.sh` repackages build 24 without a new build number (the exe's own `CompanyName` in `Runner.rc` stays `Omni` until the next build unless changed too). Keeping `Omni` also works. |

Not a blocker: code signing. Winget accepts unsigned installers, but users get a SmartScreen prompt, and new unsigned binaries are flagged by Defender more often in validation. Plan to add signing later (Azure Trusted Signing or an OV certificate) and sign both `verbnest_app.exe` and the setup in `package_windows.sh`.

## Steps

Owner = needs your accounts or a decision; Agent = Claude can do it.

### 1. Decisions (Owner)

- ⏳ Public host for installers (B1). Recommended: `bulhanb/verbnest-releases`.
- ⏳ Publisher name (B3).
- ⏳ Licence wording and whether a terms URL exists (B2).
- ⏳ Which GitHub account opens the winget PR. The fork of `microsoft/winget-pkgs` and the PR are public and show the account name.

### 2. Prepare the installer (Agent)

- ⏳ If the publisher changes: set `AppPublisher` in `distribution/windows/verbnest.iss` (and `CompanyName` in `Runner.rc` for the next build), repackage with `SKIP_BUILD=1 scripts/package_windows.sh`.
- ⏳ Test the installer in Windows Sandbox (clean machine): silent per-user install (`/VERYSILENT /SUPPRESSMSGBOXES /NORESTART /CURRENTUSER`), silent machine install (`/ALLUSERS`, elevated), app starts, Start menu entry, reinstalling over an existing install keeps the workspace, silent uninstall removes the app and the Apps & Features entry. Record results in `docs/release/device-checklist.md`.
- ⏳ Check the Apps & Features entry: `DisplayName=VerbNest`, `DisplayVersion=0.59.3`, `Publisher` as decided, product code `{4831FE71-9D3A-4C42-B468-657CE7AA76F2}_is1`.

### 3. Host the installer publicly (Owner creates repo, Agent uploads)

- ⏳ Create the public repo (README only: what VerbNest is, link to download).
- ⏳ Create release `v0.59.3` there and upload the installer. The asset URL becomes `https://github.com/bulhanb/verbnest-releases/releases/download/v0.59.3/VerbNest-0.59.3+<build>-windows-x64-setup.exe`. Assets must never be replaced after submission: winget pins the SHA-256.

### 4. Write and validate the manifests (Agent)

- ⏳ Install `wingetcreate` (`winget install Microsoft.WingetCreate`).
- ⏳ `wingetcreate new <public installer URL>` to fill in the SHA-256 and installer type, then edit to match the drafts below. Keep a copy in `distribution/winget/manifests/o/Omni/VerbNest/0.59.3/` (same layout as `winget-pkgs`).
- ⏳ `winget validate distribution/winget/manifests/o/Omni/VerbNest/0.59.3`.
- ⏳ In Windows Sandbox: `winget settings --enable LocalManifestFiles`, then `winget install --manifest <dir>`, `winget list Omni.VerbNest` (shows the package as installed, which proves the Apps & Features match), `winget uninstall Omni.VerbNest`.
- ⏳ Update `distribution/winget/README.md` (identifier, how to update).

### 5. Submit (Owner approves, Agent runs)

- ⏳ `wingetcreate submit --token <GitHub token> <manifest dir>`. It forks `microsoft/winget-pkgs` and opens the PR.
- ⏳ Sign the Microsoft CLA when the bot asks on the PR (once per account).
- ⏳ Watch the PR: automated validation (installs in a VM, Defender scan, URL checks), then moderator review. Answer labels such as `Needs-Author-Feedback`. Expect a few days. The package is installable once the PR merges.

### 6. Later releases (Agent)

- ⏳ After each Windows build: upload to the public repo, then `wingetcreate update Omni.VerbNest --version <version> --urls <url> --submit --token <token>`.
- ⏳ Add this to the release workflow: roadmap rule 7 and phase-commit step 8 mention the upload and the `wingetcreate update` call. Optionally a `scripts/publish_winget.sh` that does both.
- Winget versions are the app version (`0.59.3`); the build number appears only in the file name. A new winget version needs a new app version, so a chore build with the same version cannot be resubmitted.

## Draft manifests (schema 1.10.0; use what `wingetcreate` generates if newer)

`Omni.VerbNest.yaml`

```yaml
PackageIdentifier: Omni.VerbNest
PackageVersion: 0.59.3
DefaultLocale: en-US
ManifestType: version
ManifestVersion: 1.10.0
```

`Omni.VerbNest.installer.yaml`

```yaml
PackageIdentifier: Omni.VerbNest
PackageVersion: 0.59.3
InstallerType: inno
UpgradeBehavior: install
ProductCode: '{4831FE71-9D3A-4C42-B468-657CE7AA76F2}_is1'
AppsAndFeaturesEntries:
  - DisplayName: VerbNest
    Publisher: Omni            # or the legal name (B3)
    DisplayVersion: 0.59.3
    ProductCode: '{4831FE71-9D3A-4C42-B468-657CE7AA76F2}_is1'
Installers:
  - Architecture: x64
    Scope: user
    InstallerUrl: https://github.com/bulhanb/verbnest-releases/releases/download/v0.59.3/VerbNest-0.59.3+24-windows-x64-setup.exe
    InstallerSha256: <from wingetcreate>
    InstallerSwitches:
      Custom: /CURRENTUSER
  - Architecture: x64
    Scope: machine
    InstallerUrl: https://github.com/bulhanb/verbnest-releases/releases/download/v0.59.3/VerbNest-0.59.3+24-windows-x64-setup.exe
    InstallerSha256: <from wingetcreate>
    InstallerSwitches:
      Custom: /ALLUSERS
ManifestType: installer
ManifestVersion: 1.10.0
```

`Omni.VerbNest.locale.en-US.yaml`

```yaml
PackageIdentifier: Omni.VerbNest
PackageVersion: 0.59.3
PackageLocale: en-US
Publisher: Omni                # or the legal name (B3)
PackageName: VerbNest
Moniker: verbnest
License: Proprietary
ShortDescription: 'Local-first API client: send HTTP requests, keep everything on your device.'
Tags:
  - api-client
  - http
  - rest
  - graphql
  - websocket
ReleaseNotesUrl: https://github.com/bulhanb/verbnest-releases/releases/tag/v0.59.3
ManifestType: defaultLocale
ManifestVersion: 1.10.0
```

`PublisherUrl`, `PrivacyUrl` (the privacy policy from `docs/release/privacy-policy.md`), `LicenseUrl` and a longer `Description` (from `docs/release/store-listing.md`) are added once there are public URLs.

## Risks

- Defender or SmartScreen flags the unsigned build during validation. Mitigation: signing (see above); otherwise reply on the PR and resubmit.
- The Inno installer offers a scope dialog (`PrivilegesRequiredOverridesAllowed=dialog`). In silent mode `/CURRENTUSER` and `/ALLUSERS` choose the scope; step 2 confirms this before submission.
- The Windows app has had only a launch check. Step 2's sandbox test is the first real install, upgrade and uninstall check.
