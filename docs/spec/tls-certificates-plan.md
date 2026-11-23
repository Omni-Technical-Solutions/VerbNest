# Certificate-based authentication: TLS and mTLS

Status 2026-11-23: Phases A (0.66.0), B (0.67.0), C (0.68.0) and D (0.69.0) done; E to K not started. Phase D note: `--pin` takes `host[:port]=sha256` (a bare hash cannot say which host it is for); WebSocket and SSE are not pinned. Owner decisions of the same day are in section 0 and are built into the phases below. Requirement: FR-HTTP-013 (client certificates per host pattern, PEM and PKCS#12, custom CA bundle) is marked P1 in `requirements.md`; this plan finishes and hardens it.

## 0. Owner decisions (2026-11-23)

1. **The CLI reads the certificates stored in the app** on the same machine (and also accepts files). Phase C is rewritten for it.
2. **Pinning is on by default** (trust on first use) for every host that has a saved client certificate. Phase D is rewritten for it.
3. **Keystore identities are wanted**, first for macOS, Android, iOS and Linux (Windows later). Section 6 becomes Phases G to K, starting with a spike.

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

- **Keep the file-based model as the base** (PEM/PKCS#12 bytes imported into VerbNest). It works on all five platforms; the key stays in the OS secret store. Keystore identities (section 6) are added beside it, not instead of it.
- **No private key in the workspace file, snapshots, history, logs, exports or the console.** Certificates and keys are device-local, as now. The one exception is the deliberate "Export for the command line" file of Phase C, which the person asks for and which is encrypted with a passphrase they type. A snapshot export carries host patterns and certificate names only (so a team sees "uses a client certificate for api.example.com" but must import its own).
- **Passphrases never go on a command line** (visible in `ps`): the CLI reads them from an environment variable or a file.
- **No new entitlement for the file-based phases (A to F).** File import uses `files.user-selected.read-write`, which the Mac build has. Phase H may add the sandbox smart-card entitlement on macOS; that is decided and noted for App Review when it is built.
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

How the CLI finds the app's certificates: the certificate bytes are in the app's local database (key `network` in the per-workspace key/value store, the same `LocalStore` file the CLI already opens for `--history`), and the private key and passphrase are in the OS secret store under `verbnest.secrets.<workspaceId>`, which `--vault` already reads (`SystemSecretVault`). So:

- `verbnest run --app-network` reads the workspace's network settings (proxy, CAs, client certificates with patterns, pins) from the app's store and, with `--vault`, the keys and passphrases. It prints one line naming the entries it will use. Without `--vault` entries that need a key are listed and skipped with an error that names the flag.
- **Limits that need a fallback.** The Mac App Store build is sandboxed: its database sits in `~/Library/Containers/com.omni.verbnest/...` and its Keychain items belong to the app's access group, so a command-line tool cannot read the keys. The app therefore gets **Settings > Network > Export for the command line**: it writes one file (`verbnest-network.json`) with the entries and keys, protected by a passphrase the person types (PBKDF2 plus AES-GCM; Dart `cryptography` or `pointycastle` to be chosen in Phase A), and the CLI reads it with `--network-config <file> --network-config-passphrase-env VAR`. This is also the way to carry the setup to CI. DMG, Linux and Windows builds are not sandboxed, so `--app-network --vault` works for them.
- Direct files stay supported: `--ca <file>` (repeatable), `--cert <file>`, `--key <file>`, `--cert-host <pattern>` (default `*`), `--cert-passphrase-env <VAR>` and `--cert-passphrase-file <file>`, `--tls-min <1.2|1.3>`, `--pin <sha256>` (repeatable), `--insecure` as today.
- Passphrases are never accepted as plain arguments (visible in `ps`).
- Two new commands: `verbnest tls inspect <file>` prints a certificate's details. `verbnest tls check <url>` performs the handshake and prints the server chain, the pin state and whether a client certificate was configured. Exit codes: 0 ok, 1 handshake failure, 2 certificate unreadable, 3 pin mismatch.
- Reports (JSON, JUnit, HTML) never contain key material or passphrases (a test scans a report for the key's base64).
- Tests: CLI tests against the mutual-TLS server in `network_test.dart` for each source (`--app-network` with a temporary store and a fake vault, `--network-config`, direct files); usage text; a page "Using client certificates in CI".

### Phase D: server verification controls (minor)

- Settings: "Minimum TLS version" (1.2 default, 1.3) through `SecurityContext.minimumTlsProtocolVersion`.
- **Pinning on by default (trust on first use).** For every host that matches a saved client certificate, the first successful verified connection records the SHA-256 of the server's public key (SPKI, so a renewed certificate with the same key still passes) and, as a second hash, of the leaf. Later connections compare after the handshake and close on mismatch. The response shows a `TlsError` naming expected and actual fingerprints and, in the app, a dialog: "The server certificate changed. Trust the new one / Keep blocking", with the old and new subject, issuer and expiry. A pin can be viewed, edited, replaced or removed per host, and pinning can be switched off per host. With verification off, nothing is recorded or checked (and the warning says so). The CLI cannot ask: a mismatch is exit code 3 unless `--trust-changed` is given; pins come from the app store, `--network-config` or `--pin`, and `--pin-file <file>` lets CI keep its own.
- Rotation is the main false-positive risk: pinning the key rather than the certificate, showing the old and new values side by side and a one-click replace keep it from becoming a nuisance. The first connection is unprotected by definition (that is the meaning of trust on first use) and the setting text says so.
- "Test connection" in the certificate list and in the request's TLS panel: handshake only, shows the chain presented (leaf), the fingerprint, names covered, validity, whether the host name matches, and the client certificate that would be offered. Warn when the leaf expires in under 30 days.
- Tests: first use records a pin, same key with a renewed certificate passes, a different key is blocked, replace and remove work, no pin is recorded when verification is off or the handshake failed, minimum version against a server limited to TLS 1.2 (`test_server` option), handshake-only does not send a request.

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

## 6. Keystore identities (Phases G to K; decision: macOS, Android, iOS, Linux first)

A keystore identity is a certificate and private key held by the operating system (a non-exportable key, a smart card or token, an enterprise-issued identity). `dart:io` cannot use one: its TLS signs with key bytes it holds itself. Only the TLS handshake has to move to the platform; VerbNest's own HTTP code (timings, HTTP/2, proxies, redirects, cookies) should stay.

**Design (to be proved by the spike).** An in-process native TLS relay per platform: Dart connects to `127.0.0.1:<port>` in plain TCP (inside the app's own process, no new process) and the native side opens the real TLS connection with the chosen identity and pipes bytes both ways; it also reports the server certificate details back for the TLS panel. A `ClientIdentity` type (file bytes or keystore reference) selects the path per host entry, and `TlsConfig.contextFor` is used only for file identities. Alternatives if the spike shows trouble: a native `HttpClient`-style adapter for those hosts only (loses VerbNest's timings and h2 handling for them), or a platform channel streaming bytes (slower, same shape as the relay). The Mac App Store build already has `network.server` (loopback listeners are what it is for); iOS and Android allow loopback sockets without an entitlement.

**Phase G: spike (about one week, one platform pair at a time, behind a debug switch).** For each platform a minimal module that opens TLS with an identity and relays 1 MB each way: Apple `Network.framework` (`NWProtocolTLS` with `sec_protocol_options_set_local_identity`), Android `SSLSocket` with an `X509ExtendedKeyManager` over `AndroidKeyStore`, Linux PKCS#11 through OpenSSL's pkcs11 provider or NSS. Measure throughput, latency, memory and the size of the added dependency, and write the result into this plan. Nothing ships from the spike.

**Phase H: macOS and iOS (together; one Security.framework code base).**
- Identities: import a PKCS#12 into the app's keychain as **non-extractable** (`kSecAttrIsExtractable = false`, so the key never enters Dart memory, which is better than today's file model) and use it through `SecIdentity`; list and remove identities in Settings. On macOS add a smart-card path through CryptoTokenKit (the sandbox entitlement `com.apple.security.smartcard`; this is a new entitlement and needs App Review notes ready: "used only for client-certificate TLS with a card the user inserted"). Identities from the user's login keychain are not visible to a sandboxed app, so the DMG build (not sandboxed) offers them and the App Store build offers the app's own keychain only.
- iOS: app keychain import only (no smart card support planned); the keychain access group stays the app's own.
- Tests: native unit tests (XCTest) for import and relay, integration tests against the mutual-TLS server, the physical-device walk-through updated.

**Phase I: Android.** `AndroidKeyStore` import of a PKCS#12 (`KeyProtection` with `setUserAuthenticationRequired` optional) and the system `KeyChain.choosePrivateKeyAlias` for certificates installed in Settings (which also covers enterprise-managed identities and hardware-backed tokens); `X509ExtendedKeyManager` that returns the chosen alias; relay over `SSLSocket`. Tests: Android instrumentation tests on the emulator, a device check with a real PKCS#12.

**Phase J: Linux.** Two sources: PKCS#11 (smart cards, tokens; module path and `pkcs11:` URI, PIN entered at use and never stored) and the NSS database in `~/.pki/nssdb` that Chrome and Firefox share. Implementation by FFI to OpenSSL 3 with the pkcs11 provider (or libcurl if the spike says it is the lighter route). The packages (`.deb`, AppImage if any) must not hard-depend on the provider; the feature appears when the library is found. Tests: SoftHSM in CI on Linux.

**Phase K: Windows (later).** Certificate Store identities through Schannel (`SCH_CREDENTIALS`), after the four above have shipped.

**Common rules.** No key material is ever copied out of a keystore; a PIN or passphrase is asked for when needed and not stored by VerbNest; the CLI can use keystore identities only on the platform that holds them (`--identity <label>`), asking for the PIN on the terminal; failures name the stage (identity not found, PIN wrong, token absent, handshake refused). Docs, threat model and store review notes are updated in each phase.

Estimate after the spike: macOS and iOS about two weeks together, Android about two weeks, Linux about two to three weeks, Windows about two weeks later. The spike's measurements replace these.

## 7. Risks and open questions

- **PKCS#12 variety.** The TLS library behind `dart:io` may reject some encryption schemes (old RC2-40, new PBES2 variants). Phase A's test table decides the user-facing message; a fallback is converting the bundle in Dart (a PKCS#12 reader dependency), which adds size and review surface and is not planned.
- **Certificate parser dependency.** A small in-house ASN.1 reader is about 300 lines and needs the fuzz test; the `x509`/`asn1lib` packages would shorten it. Decide in Phase A by checking their licences and Dart 3.14 compatibility.
- **Windows tests.** OpenSSL may be absent on the Windows runner; keep the skip and run the mutual-TLS tests on Linux and macOS.
- **Keystore scope creep.** Smart cards and enterprise identities vary a lot; each platform's first release supports one clear path (macOS/iOS app keychain, Android KeyStore and KeyChain, Linux PKCS#11 and NSS) and lists the rest as not supported.
- **Trust on first use and rotation.** See Phase D; if pin prompts annoy in practice, relax to "warn once per change" rather than silently trusting.
- **No open questions for the owner** at this point; the three asked on 2026-11-23 are answered in section 0.

## 8. Order and size

A (3 to 4 days), B (2), C (4 to 5, larger now: app store, export file, vault), D (4 to 5 with pinning by default), E (2), F (1): about four weeks for the file-based work. G (spike, 1 week) can run beside B to F; H to J follow it: another five to seven weeks, then K. Do A first: it fixes the most common failure (finding out at send time).
