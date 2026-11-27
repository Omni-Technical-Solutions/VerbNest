# Plan: the private key cannot be chosen for a PEM certificate

Status: done in 0.73.3. Planned release type: `fix` (patch). Reported 2026-11-27 while testing certificate upload: after choosing a certificate the dialog says "This is a PEM certificate: choose its private key as well" and Add stays off, but there is no way to choose the key.

## Verified: it happens, and why

Reproduced with a widget test (temporary, deleted again) on the real `_ClientCertDialog`: a PEM certificate with a short text header in front of the `-----BEGIN CERTIFICATE-----` line.

| Header before `-----BEGIN` | Message "choose its private key" | Key row (`pick-key`) | Add |
|---|---|---|---|
| none (a plain `.pem`) | shown | **shown** | on after the key is chosen |
| 94 bytes (`Bag Attributes`, `localKeyID`, `subject=`, `issuer=`) | shown | **missing** | off, nothing to press |
| 299 bytes (the same with longer subject lines) | not shown (see below) | **missing** | off |

Cause: the dialog and the certificate check decide "is this a PEM file" differently.

- The dialog (`_isPem` in `apps/verbnest_app/lib/src/widgets/network_settings.dart:345`) looks for `-----BEGIN` in the first **80** bytes and shows the key row only if it finds it.
- The check (`_isPem` in `packages/verbnest_http/lib/src/cert_check.dart:177`) looks in the first **200** bytes and answers `keyMissing` ("choose its private key as well").
- A file with 80 to 200 bytes of text first passes the check and fails the dialog: the message is on screen, the control it points to is not. Files with more than 200 bytes of text first fail both and are treated as a PKCS#12 bundle, so the person gets a passphrase or format message for a file that is a PEM.
- Text before the first block is normal, not rare: `openssl pkcs12 -in file.p12 -nodes` and `-out` write `Bag Attributes` and `subject=`/`issuer=` lines before every block, and some CAs add a descriptive header. OpenSSL (and so `dart:io`) ignores that text when it loads the file, so the file is valid.
- The same 200-byte rule is copied in four more places: `packages/verbnest_runner/lib/src/network_settings.dart:54`, `packages/verbnest_cli/lib/src/tls_commands.dart:141` and `tls_options.dart:410`. They give the CLI and the runner the same wrong answer for such a file. (`cert_check.dart:264` and `cert_inspect.dart:100` already search the whole file.)

The Headers tab uses the same dialog (`showClientCertDialog`), so it is affected as well as Settings.

## Fix

1. **One detector, in `verbnest_http`.** Export `bool looksLikePem(Uint8List bytes)` (and, next to it, `hasPrivateKeyBlock`, which the app already has as `_hasPrivateKey`). It searches the whole file for `-----BEGIN ` (files are small; cap the search at 1 MB so a huge file is not decoded). A binary PKCS#12/DER file has no such text, so it is still not a PEM.
2. **Use it everywhere the rule is copied:** the app dialog, `checkClientCertificate`, the runner, and both CLI places. Delete the local copies, so the dialog and the check cannot disagree again.
3. **Belt and braces in the dialog:** show the key row when `looksLikePem` is true **or** the check answered `keyMissing`. The message can then never appear without the control it asks for.
4. **Header text is skipped, not stored wrongly.** Confirm with a fixture that `parseCertificate`, `SecurityContext.useCertificateChainBytes` and `usePrivateKeyBytes` all accept a certificate and a key with text in front. If one does not, strip everything before the first `-----BEGIN` when the file is read, and keep the original bytes out of storage.
5. **Wording.** The 299-byte case in the table: after step 1 it takes the PEM path, so it gets the same "choose its private key as well" and the key row. Nothing else to word.

## Tests

- `packages/verbnest_http`: `looksLikePem` for a plain PEM, a PEM with a 94-byte and a 300-byte header, a PEM with Windows line endings (CRLF), a DER file, a PKCS#12 file, an empty file. `checkClientCertificate` with a headed certificate: `keyMissing` without a key, ok with a key (including a headed key file). Made with `openssl`, skipped when it is missing (not in CI: `CI=true` already fails instead).
- `apps/verbnest_app/test/client_cert_dialog_test.dart`: the two headed cases from the table. The key row is there, choosing a key turns Add on, and the saved entry keeps the key. A combined headed PEM (certificate and key in one file) takes its key from the same file. Keep the existing plain-PEM test.
- A guard test that fails if `take(80)`, `take(200)` and `.contains('-----BEGIN')` appear together again outside the detector (a plain source scan, like the existing guard tests).
- Runner and CLI: one test each with a headed certificate, so `verbnest run` and the TLS commands accept it.
- Manual, on a phone and a desktop: export a PKCS#12 to PEM with `openssl pkcs12 -nodes`, split into certificate and key, add both in Settings and from the Headers tab, then **Test connection** against a mutual-TLS host (the repo's `test_server` has one).

## Risks

| Risk | Mitigation |
|---|---|
| A PKCS#12 file that happens to contain the text `-----BEGIN` is now taken for a PEM | Binary PKCS#12 is DER and compressed or encrypted; the check also needs a parseable certificate block, and a failure still names the file type. Test with a real `.p12`. |
| A stored entry (made before the fix) whose certificate has a header and no key | It was never saved, since Add was off, so none exist. A headed certificate with a combined key was saved only if its key was in the first bytes; reopen such an entry in the test to be sure. |
| Changing shared code in `verbnest_http`, runner and CLI | One function, called from five places, each covered by a test above; no behaviour changes for files that start with `-----BEGIN`. |

## Out of scope

- A PEM file picker filter (`.pem`, `.crt`, `.key`): the picker already accepts any file, and key files are often named `.key`; the button says "(.pem)" only as a hint. Changing that label to "private key file" is a one-line follow-up if you want it.
- Encrypted-key handling, PKCS#8 versus traditional keys: unchanged.

## Release

`fix` per `docs/spec/roadmap.md` (Release workflow): analyze and tests green, `CHANGELOG.md` entry ("Fix: a PEM certificate with text before its first block (the `Bag Attributes` lines `openssl pkcs12` writes) now asks for its private key, and the key can be chosen"), `scripts/bump_version.sh fix` (0.73.3), annotated tag, `scripts/security_scan.sh` and `/security-review` before anything is published, then the builds. Pushing and publishing stay manual.
