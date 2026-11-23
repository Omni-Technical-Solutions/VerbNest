# Keystore identities on Linux and Windows: enabling and testing

The Linux and Windows parts of FR-HTTP-013f (`packages/verbnest_keystore/linux`
and `packages/verbnest_keystore/windows`) were written without a Linux or
Windows machine to build on. **They have never been compiled or run.** Flutter
does not build them because `packages/verbnest_keystore/pubspec.yaml` lists the
plugin only for macOS, iOS and Android; until it is listed, those platforms
report "no keystore" and the button does not appear. This page is how to switch
them on and what to check.

## Linux (GnuTLS, PKCS#11)

Design: GnuTLS opens the TLS connection with a certificate and key named by
`pkcs11:` URLs (any module p11-kit knows: smart cards, tokens, NSS). A loopback
relay hands the bytes to VerbNest.

1. Install the build dependency: `sudo apt install libgnutls28-dev` (and
   `p11-kit`, `opensc` or `softhsm2` to have something to test with).
2. In `packages/verbnest_keystore/pubspec.yaml` add under `flutter: plugin:
   platforms:`
   ```yaml
   linux:
     pluginClass: VerbnestKeystorePlugin
   ```
   The Linux plugin registers through `verbnest_keystore_plugin.h`; the
   generated registrant expects the class name in snake case
   (`verbnest_keystore_plugin_register_with_registrar`), which is what the
   source defines. If Flutter complains, fix the name in the pubspec to match.
3. `flutter build linux`. The code uses `apply_standard_settings` and links
   `PkgConfig::GTK`: both come from the app's own CMake, as in the Flutter
   plugin template. Expect to fix compile errors; none have been seen yet.
4. Make a test token: `softhsm2-util --init-token --slot 0 --label vn --pin 1234
   --so-pin 1234`, then import a client key and certificate with `p11tool` or
   `pkcs11-tool`, and run the mutual-TLS test server below.
5. In the app, Settings > Network > Add from the system keystore should list
   the token's certificate; a request or Test connection to the test server
   should show the client certificate offered.
6. Check: a locked token (wrong PIN) gives a readable error; the relay port
   closes after the request; `import` and `remove` answer with the message
   saying the keystore is managed outside VerbNest (by design).

## Windows (SChannel, certificate store)

Design: certificates of the current user's "MY" store whose keys are in CNG
(non-exportable, TPM, smart card). SChannel does the handshake with
`SCH_CREDENTIALS`; the server certificate is validated by VerbNest's own code
(`CertGetCertificateChain` with the system roots plus the extra CAs, then the
SSL policy with the host name) so extra CAs can count as roots. TLS 1.3 needs
Windows 11 or Server 2022.

1. In `packages/verbnest_keystore/pubspec.yaml` add
   ```yaml
   windows:
     pluginClass: VerbnestKeystorePluginCApi
   ```
2. `flutter build windows` with Visual Studio's C++ toolchain. Expect compile
   errors to fix (the SChannel structures, the ALPN buffer layout in
   `Handshake`, and the `std::variant` access on `EncodableValue` are the
   riskiest places).
3. Import a test PKCS#12 with the app's **Import** button (it goes into the
   "MY" store with a non-exportable key) or with `certutil -user -p <pass>
   -importpfx file.p12 NoExport`.
4. Check the same list as for Linux, plus: a smart-card PIN prompt appears when
   the card is used; TLS 1.2-only servers work; `--insecure`-style "verify
   off" still presents the identity.

## The mutual-TLS test server

Anywhere with OpenSSL:

```sh
openssl req -x509 -newkey rsa:2048 -nodes -keyout s.key -out s.pem -days 1 \
  -subj "/CN=localhost" -addext "subjectAltName=DNS:localhost,IP:127.0.0.1" \
  -addext "extendedKeyUsage=serverAuth"
openssl req -x509 -newkey rsa:2048 -nodes -keyout c.key -out c.pem -days 1 \
  -subj "/CN=vn-client" -addext "extendedKeyUsage=clientAuth"
openssl pkcs12 -export -in c.pem -inkey c.key -out c.p12 -passout pass:test \
  -keypbe AES-256-CBC -certpbe AES-256-CBC -macalg sha256
openssl s_server -accept 9443 -cert s.pem -key s.key -CAfile c.pem -Verify 1 \
  -verify_return_error -HTTP
```

Add `s.pem` as a CA in Settings > Network, send a request to
`https://localhost:9443/`, and the server prints the client certificate it was
shown. Apple's and Android's trust code needs the `extendedKeyUsage` lines.

## On the platforms that do work

`scripts/keystore_device_test.sh` (macOS by default, `DEVICE=<android id>` for
the emulator) runs the end-to-end integration test with the real native
plugin. iOS needs a signed device (the simulator build has no keychain
entitlement): `DEVICE=<device id> scripts/keystore_device_test.sh`.
