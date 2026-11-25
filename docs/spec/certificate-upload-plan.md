# Uploading certificates from the Headers tab (plan)

Status 2026-11-25: phases L, M, N and O implemented in 0.73.0.

Owner request (2026-11-25): "all certificates should be able to be uploaded via the UI into the header tab, create a plan to implement that includes certificate validation."

Reading of the request: today certificates are added only in Settings > Network. A request's **Headers** tab should let the person add every kind of certificate that request needs, in place, and every upload is validated before it is kept. "All certificates" means: client certificate (PEM + key, or PKCS#12), a trusted CA (PEM or DER, one or many in a file), a client certificate from the system keystore, and "send no client certificate". Pins are recorded by the engine and stay in Settings.

## Today

- Client certificate: `_ClientCertDialog` in `widgets/network_settings.dart` loads the files the way the engine does (`checkClientCertificate`): wrong passphrase, key mismatch, not a certificate, expiry and self-signed warnings. Good.
- Trusted CA: `NetworkNotifier.addCa` only checks `_looksLikeCertificate` (a PEM header or a DER start). No parse, no expiry, no load check, no feedback about what was added. This is the validation gap.
- Keystore identity: `showKeystoreCert` (macOS, iOS, Android).
- The Headers tab shows only the generated headers and the header table.

## Phases

### L. CA validation (`verbnest_http`)

`checkCaCertificates(bytes, {now})` in `cert_check.dart`:
- every certificate in the file is parsed (`parseCertificates`); a file with none, or a block that is not a certificate, is a problem with a sentence;
- the bytes are loaded into `SecurityContext(withTrustedRoots: false).setTrustedCertificatesBytes`, the call the engine makes, so a file that parses but cannot be used is caught here and not at the first request;
- result `CaCheck { message, certs, warnings }`; warnings per file: `expired`, `notYetValid`, `expiresSoon`.
Tests: a real CA, a bundle of two, a leaf-only file, garbage, an empty file, a truncated PEM, an expired CA (made with `openssl`, skipped when it is missing), DER.

### M. CA upload uses it (`verbnest_app` state)

`NetworkNotifier.addCa` returns the problem as a sentence and refuses an expired or not-yet-valid CA (it would never validate anything). Otherwise it adds the file and returns a one-line description (`subject, valid to <date>`) so the UI says what was added. A CA with the same SHA-256 already in the list is not added twice. Tests in `network_state_test` with an in-memory file port.

### N. The Headers tab section

`TlsCertificatesSection` in `widgets/request_editor/headers_tab.dart`, an expansion tile under the generated headers (like "Generated headers"):
- the host and port come from the request URL; with a variable in the host (`{{host}}`) the section works on the pattern `*` and says so;
- one line says what applies to this host: the client certificate entry that `selectFor` picks (name, pattern, expiry), "No client certificate" for a none-entry or no match, and the number of trusted CAs;
- buttons: **Add client certificate** (the existing dialog, host pre-filled with `host[:port]`), **Add trusted CA** (file picker through M), **Add from the system keystore** (where supported), **Send no client certificate** (a none entry for this host), **Test connection** (the existing probe dialog, for this URL);
- every result is saved to the same network settings, so the Settings page shows it too, and the entry is the same entry (no copies).
Shown for `https`, `wss` and variable URLs; a plain `http://` URL shows one line saying certificates apply to https only.

### O. Tests, docs, release

Widget tests for the section (line text for each case, each button opens its dialog with the host filled, adding a bad CA shows the message and keeps the list). Requirements FR-HTTP-013g, CHANGELOG, `docs/release/client-certificates.md`. Release as a minor version after the gate.

## Out of scope / decisions

- Certificates are stored once, in the network settings, not inside a request: a request or collection exported or shared must never carry a key. The Headers tab is a place to add them from, not a place to keep them.
- A CA being an actual CA (basic constraints) is not enforced; many private setups use a self-signed server certificate as its own trust anchor.
- Revocation (CRL, OCSP) is not checked; the TLS library does not expose it.
