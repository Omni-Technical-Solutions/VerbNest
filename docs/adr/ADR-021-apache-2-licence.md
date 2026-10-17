# ADR-021: Apache License 2.0

Date: 2026-10-17. Status: accepted (owner).

## Context
The repository is to become open source. Until now only `distribution/LICENSE_1_0.txt` (Boost Software License 1.0) existed, used for the installer and winget; the source root had no licence. Dependencies are all BSD, MIT or Apache (138 locked Dart packages), fonts are OFL.

## Decision
Apache License 2.0 for the code and documentation, with `LICENSE` (unmodified text) and `NOTICE` at the repo root. It is permissive, has an explicit patent grant, grants no trademark rights, and has no conflict with the App Store, Play Store or Microsoft Store. Considered and rejected: MIT (no patent grant), Boost (no patent grant, name clash with the Business Source licence), MPL-2.0, AGPL/GPL (store terms, contributors), BUSL/FSL (not open source).

## Consequences
- Applies from 0.64.4. Releases up to 0.64.3 stay under Boost 1.0; `distribution/LICENSE_1_0.txt` was removed (in git history).
- winget manifests from 0.64.4 use `License: Apache-2.0`; the Windows installer shows and installs `LICENSE` and `NOTICE`; Flatpak `project_license` is `Apache-2.0`; `LegalCopyright` (Windows) and `PRODUCT_COPYRIGHT` (macOS) name Apache 2.0.
- Names and the icon are reserved (README Licence section); the icon artwork is not under the code licence.
- Gap found while applying: the app registers the font licences in `LicenseRegistry` (main.dart) but has no page that shows licences (`showLicensePage` is not used), so binary distributions do not yet show the BSD/MIT/Apache notices of the dependencies. Add an About / Licenses page.
- Open: DCO or CLA before outside contributions, and the history question (see context.md).
