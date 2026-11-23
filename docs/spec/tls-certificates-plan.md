# Certificate-based authentication: TLS and mTLS

Status 2026-11-23: plan only; nothing implemented. Requirement: FR-HTTP-013 (client certificates per host pattern, PEM and PKCS#12, custom CA bundle) is marked P1 in `requirements.md`; this plan finishes and hardens it.

## 1. What exists today

The engine and the Settings screen already carry a first version. A plan has to start from it.

| Area | State | Where |
| --- | --- | --- |
| Custom CA bundle (PEM or DER) added to the trusted roots | Done | `TlsConfig.caCertificates`, `network_settings.dart` ("add-ca"), `NetworkNotifier.addCa` checks the file looks like a certificate |
| Client certificate per host pattern (`api.example.com`, `*.example.com`, `*`) | Done | `ClientCertificate`, `TlsConfig.contextFor(host)` |
| PEM certificate + private key, or PKCS#12 with passphrase | Done (engine tests with `openssl`) | `network_test.dart`: "a PEM client certificate is presented to matching hosts", "a PKCS#12 bundle needs the right passphrase" |
| Used by HTTP/1.1, HTTP/2, over a proxy tunnel, WebSocket and SSE | Done | `engine.dart` `_secure`, `realtime.dart` `_client` |
| Storage: certificate bytes in the device-local key/value store; private key and passphrase in the secret store (Keychain, Keystore, libsecret) | Done | `NetworkNotifier` (`secrets['key.<id>']`, `secrets['pass.<id>']`) |
| Server certificate details in the response (subject, issuer, validity, protocol) and a "client certificate sent" flag | Done, thin | `TlsInfo`, `response_panels.dart` |
| "Disable certificate verification" | Done; on a CLI run a warning is printed | `HttpSettings.verifyTls`, `cli.dart` `_httpDefaults` |
| Scripts (`pm.sendRequest`), OAuth token calls, GraphQL introspection | Use the same `HttpSettings`, so they get the same TLS material | `EngineScriptHost(settings:)`, `introspect()` |

## 2. Gaps (what the plan adds)

Ranked by what a person doing mTLS work runs into first.

1. **Mistakes show up only when you send.** The certificate dialog saves whatever files are picked. A key that does not match the certificate, a wrong passphrase, an expired certificate or a PKCS#12 the TLS library cannot read is reported at the first request as "Could not load the certificates: ...". Nothing shows the person what they imported (subject, issuer, expiry, fingerprint).
2. **The CLI and `verbnest run` cannot use any of it.** The certificates live in the app's device-local store; `_httpDefaults` in the CLI reads only the workspace's timeout, redirects and verify flag. mTLS APIs in CI are a main use of the runner.
3. **Matching is the first entry that fits.** `contextFor` takes the first matching row. There is no ordering by specificity, no `host:port` pattern, no way to say "no client certificate for this host", and entries cannot be edited or switched off.
4. **Few controls on the server side.** No minimum TLS version, no pinning of a server certificate, no handshake-only "test this host" action, and the TLS panel shows the leaf only (no fingerprint, no names it covers, no expiry warning).
5. **cURL parity.** Importing `curl --cert/--key/--cacert/--pass/--cert-type` produces "Ignored option" warnings; code generation never writes them.
6. **No operating-system keystore.** Keys that cannot be exported (smart cards, hardware tokens, Keychain/Windows-store identities, Android KeyChain) cannot be used, because `dart:io` needs the key bytes. This is a different class of work (section 6).

Known limits of `dart:io` to design around: it cannot report the negotiated TLS version or cipher, cannot tell whether the server asked for a client certificate or accepted it (the TLS panel can only say "configured for this host"), and offers the first configured certificate regardless of the server's list of accepted CAs.

## 3. Decisions taken in this plan

- **Keep the file-based model** (PEM/PKCS#12 bytes imported into VerbNest). It works on all five platforms with no new store entitlement; the key stays in the OS secret store.
- **No private key in the workspace file, snapshots, history, logs, exports or the console.** Certificates and keys are device-local, as now. A snapshot export carries host patterns and certificate names only (so a team sees "uses a client certificate for api.example.com" but must import its own).
- **Passphrases never go on a command line** (visible in `ps`): the CLI reads them from an environment variable or a file.
- **No new entitlement.** File import uses `files.user-selected.read-write`, which the Mac build has.
- **Verification stays on by default.** With verification off, VerbNest still presents a matching client certificate; a visible warning says so (the certificate is public, but a man in the middle learns who you are).

## 4. Phases

Each phase is a release on its own (version bump as in the release workflow), and ends with the tests below plus `scripts/complexity_report.py --check`.

### Phase A: check a certificate when it is imported (minor)

- New `packages/verbnest_http/lib/src/cert_inspect.dart`: parse a PEM or DER certificate (a small ASN.1 reader; no new dependency unless `x509` proves smaller to maintain) into `CertInfo`: subject, issuer, serial, validity, subject alternative names, key type and size, SHA-256 fingerprint (`crypto` is already a dependency), self-signed flag. Add the same fields to `TlsInfo` (fingerprint and names for the server certificate).
- New `validateClientCertificate(bytes, key?, passphrase)`: builds a `SecurityContext` with the material (so exactly what the engine will do) and returns a result: ok, or a specific reason (wrong passphrase, key does not match, unsupported PKCS#12 encryption, not a certificate, expired, not yet valid). PKCS#12 shows "valid" without details (the library does not expose them); PEM shows the details.
- The certificate dialog calls it before "Save" and shows the details and any warning (expires in under 30 days, expired, self-signed, `*` pattern); the list rows show "expires 2027-03-01" in the colour of the warning.
- Tests: unit tests with certificates made by `openssl` in `test_server` (the existing `TestServer.selfSignedCertificate`, `pkcs12`): matching and mismatched key, encrypted PKCS#8 key (right and wrong passphrase), EC and RSA keys, a chain in one PEM, PKCS#12 made by OpenSSL 3/4 defaults and with `-legacy` (3DES/RC2), expired and not-yet-valid certificates (`-days`, `-startdate`). A table of what the platform library accepts goes into the docs; unsupported ones get the message "re-export with `openssl pkcs12 -export -legacy`" or the modern equivalent, whichever works.
- Widget tests for the dialog states.

### Phase B: matching rules and management (minor)

- Choose the entry by specificity: exact host, then `*.suffix` (longest first), then `*`; support `host:port` and `https://host:port` patterns; an entry can be switched off and edited; a "none" entry (`certificate: none`) stops a broader pattern from applying to a host.
- `ClientCertificate` gets `enabled`, `port`, an optional `label`. `NetworkNotifier` stores the new fields with a version bump of its JSON (old data reads unchanged).
- The TLS panel names which entry applied ("Client certificate 'Staging API' (configured)").
- Tests: pattern table (`matches`, ordering), migration of stored configs, the TLS panel text.

### Phase C: the CLI and the runner (minor)

- `verbnest run` (the only CLI command that sends requests; the others are `mock` and `history`) gains: `--ca <file>` (repeatable), `--cert <file>`, `--key <file>`, `--cert-host <pattern>` (default `*`), `--cert-passphrase-env <VAR>` and `--cert-passphrase-file <file>`, `--tls-min <1.2|1.3>`, `--pin <sha256>`; the existing `--insecure` stays. Certificates are not read from the app's device store (the CLI has no access to it by design); the workspace file carries host patterns only, so a CI job supplies the files.
- Optional `--network-config <json>`: the same shape the app stores, for CI secrets mounted as files.
- Two new commands, `verbnest tls inspect <file>` and `verbnest tls check <url> [--cert ...]`. The first prints a certificate's details. The second performs the handshake and prints the server chain and whether a client certificate was configured. Exit codes: 0 ok, 1 handshake failure, 2 certificate unreadable.
- Reports (JSON, JUnit, HTML) never contain key material or passphrases (add a test that scans a report for the key's base64).
- Tests: CLI tests against the mutual-TLS server in `network_test.dart`; usage text; `docs` page "Using client certificates in CI".

### Phase D: server verification controls (minor)

- Settings: "Minimum TLS version" (1.2 default, 1.3) through `SecurityContext.minimumTlsProtocolVersion`; per host "Pin server certificate" (SHA-256 of the leaf, check after the handshake and close on mismatch; the response shows a TlsError that names expected and actual fingerprints). Pins are stored next to the host patterns.
- "Test connection" in the certificate list and in the request's TLS panel: handshake only, shows the chain presented (leaf), the fingerprint, names covered, validity, whether the host name matches, and the client certificate that would be offered. Warn when the leaf expires in under 30 days.
- Tests: pin accepted and rejected, minimum version against a server limited to TLS 1.2 (`test_server` option), handshake-only does not send a request.

### Phase E: cURL parity (patch/minor)

- Import: map `--cacert`, `--cert` (with `:password`), `--key`, `--cert-type`, `--pass`, `-k` into a suggested certificate entry for the host. The files are paths on another machine, so the import dialog lists them ("this command used client certificate client.pem: add it under Settings > Network") instead of reading them.
- Export: when a client certificate or CA is configured for the host, generated cURL contains `--cert <file> --key <file>` with placeholder names (never the key); other code generators get a comment.
- Tests: `curl.dart` import table, `codegen` output.

### Phase F: documentation, threat model, release notes (chore)

- `docs/release/` user page "Client certificates and mutual TLS" (formats, how to convert, what is stored where, CI use); `threat-model.md` rows: key at rest, cleartext in memory, passphrase handling, unverified server plus client certificate, pinning; `requirements.md`: split FR-HTTP-013 into FR-HTTP-013a (import validation), 013b (matching), 013c (CLI), 013d (pinning and minimum version), 013e (cURL parity). `store-listing.md` review notes: client certificates are user-supplied files, no hardware access.

## 5. Test strategy

- Extend `test_server` with: a mutual-TLS option that requires a client certificate and answers with the subject; an option that limits the maximum TLS version; one that serves an expired certificate; a PKCS#12 factory with the legacy and modern encryption options. They use `openssl` (present on the CI Linux and macOS runners; Windows tests skip when it is missing, as `network_test.dart` already does).
- Property: no log line, history entry, report or exception message contains a private key or passphrase (extend the masker tests).
- Fuzz test for the certificate parser (the project's fixed-seed fuzz pattern): any bytes give a result or a typed error, never an uncaught exception.
- On-device check (iPhone, Android phone, Mac, Windows, Linux): import a PKCS#12 with the platform file picker and send to a real mTLS test endpoint. The App Review walk-through test and recording (`docs/release/app-review-recording.md`) can include the import dialog after Phase A.

## 6. Operating-system keystores (separate decision, not in the phases above)

Using identities from the macOS Keychain, the Windows certificate store, Android KeyChain or a smart card needs the platform's own TLS stack, because the key cannot leave the secure element and `dart:io` signs with key bytes it holds itself. Two routes:

1. A native adapter per platform (`URLSession` with `SecIdentity`, `HttpClient` with `KeyChain`/`KeyManager`, `WinHTTP`/Schannel) behind the existing `HttpEngine` interface, used only for hosts that pick a keystore identity. It loses VerbNest's own timings, redirect and proxy handling for those requests unless re-implemented.
2. A local TLS-terminating helper process. Rejected: more moving parts and a listening socket in the sandboxed builds.

Estimate: two to three weeks per platform with tests on devices, and App Review notes. Recommend deciding after Phases A to D have shipped and users ask for it.

## 7. Risks and open questions

- **PKCS#12 variety.** The TLS library behind `dart:io` may reject some encryption schemes (old RC2-40, new PBES2 variants). Phase A's test table decides the user-facing message; a fallback is converting the bundle in Dart (a PKCS#12 reader dependency), which adds size and review surface and is not planned.
- **Certificate parser dependency.** A small in-house ASN.1 reader is about 300 lines and needs the fuzz test; the `x509`/`asn1lib` packages would shorten it. Decide in Phase A by checking their licences and Dart 3.14 compatibility.
- **Windows tests.** OpenSSL may be absent on the Windows runner; keep the skip and run the mutual-TLS tests on Linux and macOS.
- **Questions for the owner:** (1) is the CLI in Phase C enough for CI users, or must the app's stored certificates be readable by the CLI on the same machine? (2) should pinning be on by default for a host once a certificate is saved (trust on first use), or only when switched on? (3) is the keystore work (section 6) wanted at all, and for which platform first?

## 8. Order and size

A (3 to 4 days), B (2), C (3 to 4), D (3), E (2), F (1). Do A first: it fixes the most common failure (finding out at send time). B and C can go in either order. About three weeks in total before section 6.
