# Contributing to VerbNest

Thanks for helping. VerbNest is a local-first API client written in Flutter. Bug reports, fixes, tests, docs and focused features are all welcome.

## Before you start
- Search the [issues](https://github.com/Omni-Technical-Solutions/VerbNest/issues) first. For a larger change, open an issue to talk it through before writing code.
- Read the principles in [docs/spec/constitution.md](docs/spec/constitution.md): local-first, no account, no telemetry, secrets stay on the device, no animation ([ADR-020](docs/adr/ADR-020-no-animation.md)), English only ([ADR-017](docs/adr/ADR-017-english-only.md)).
- Security problems go to [SECURITY.md](SECURITY.md), not to a public issue.
- By taking part you agree to the [Code of Conduct](CODE_OF_CONDUCT.md).

## Developer Certificate of Origin (DCO)
Every commit must carry a sign-off line saying you have the right to submit it under the project's licence ([Apache-2.0](LICENSE)). This is the [Developer Certificate of Origin 1.1](https://developercertificate.org/):

> By making a contribution to this project, I certify that:
> (a) The contribution was created in whole or in part by me and I have the right to submit it under the open source license indicated in the file; or
> (b) The contribution is based upon previous work that, to the best of my knowledge, is covered under an appropriate open source license and I have the right under that license to submit that work with modifications, whether created in whole or in part by me, under the same open source license (unless I am permitted to submit under a different license), as indicated in the file; or
> (c) The contribution was provided directly to me by some other person who certified (a), (b) or (c) and I have not modified it.
> (d) I understand and agree that this project and the contribution are public and that a record of the contribution (including all personal information I submit with it, including my sign-off) is maintained indefinitely and may be redistributed consistent with this project or the open source license(s) involved.

Add the line with `git commit -s`:

```
Signed-off-by: Your Name <you@example.com>
```

The name and email must match the commit author. A pull request check fails if a commit has no sign-off. To fix one: `git commit --amend -s --no-edit`; for several: `git rebase --signoff main`, then force-push your branch.

There is no CLA. You keep the copyright in your contribution.

## Set up
You need the Flutter stable SDK (the Dart constraint is in `pubspec.yaml`) and, for the JavaScript engine, a Rust toolchain (`rustup`). Then:

```sh
flutter pub get                      # workspace root
cd apps/verbnest_app
flutter run -d macos                 # or linux, windows, an Android or iOS device
```

## Checks (run these before a pull request)
```sh
dart format --output=none --set-exit-if-changed packages test_server apps/verbnest_app/lib apps/verbnest_app/test
dart analyze packages test_server
(cd packages/verbnest_core && dart test)   # and the other packages, see .github/workflows/ci.yml
cd apps/verbnest_app
flutter analyze
flutter test --exclude-tags golden
```

Golden (screenshot) tests are tagged `golden` and are made on macOS; CI compares them on macOS only. If you change the look on purpose, run `flutter test --update-goldens --tags golden` on macOS and include the new pictures.

## Pull requests
- Keep them small and about one thing. Add or update tests, and docs when behaviour changes.
- Add a line to `CHANGELOG.md` for anything a user would notice.
- Follow the surrounding code style; `dart format` decides layout.
- The UI is English only and has no animations: do not add transitions, fades or implicit animations.
- Do not commit secrets, signing keys, personal data or generated build output.

## Licence of contributions
Contributions are licensed under the Apache License 2.0, as the rest of the project. The names "VerbNest" and "Omni" and the VerbNest icon are not part of that licence; see [TRADEMARK.md](TRADEMARK.md).
