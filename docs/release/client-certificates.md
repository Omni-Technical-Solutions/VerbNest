# Client certificates and mutual TLS

Some servers ask the client to prove who it is with a certificate (mutual TLS,
mTLS). VerbNest sends the certificate you give it to the hosts you choose, and
checks the server's key so a changed server does not go unnoticed.

## What it accepts

- **PEM**: a certificate file and, separately, its private key (`.pem`, `.crt`,
  `.key`). An encrypted key needs its passphrase.
- **PKCS#12** (`.p12`, `.pfx`): certificate and key in one file, with its
  passphrase. Files made with very old encryption (RC2, 3DES) may not open:
  convert them with
  `openssl pkcs12 -in old.p12 -nodes -out all.pem` and import the PEM, or
  re-export with modern encryption.
- A **CA certificate** (PEM or DER) to trust in addition to the system roots.

Every file is checked when you add it: a wrong passphrase, a key that does not
match, or a file that is not a certificate is reported at once, with the
reason. An expired, not-yet-valid, soon-to-expire (under 30 days) or
self-signed certificate gets a warning.

## Which host gets which certificate

Each entry names the hosts it applies to: an exact host, `*.example.com` or `*`,
with an optional `:port`. The most specific entry wins (exact host, then the
longest wildcard, then `*`; a pattern with a port beats the same without), so the
order of the list does not matter. An entry can be switched off, edited, or set
to **send no client certificate** to the hosts it names (to stop a broad `*`
entry leaking your certificate to a host that does not need it).

## Where things are kept

| What | Where |
| --- | --- |
| Certificates, CA files, host patterns, pins | The workspace's device-local store on this computer; not in the workspace file, so they do not travel when you share a workspace |
| Private keys, key passphrases, the proxy password | The system secret store (Keychain, Credential Manager, libsecret) |
| Keys in use | In memory for the TLS library while a request is made |

Keys are never written to history, the console, run reports, exports of
workspaces or generated code. **Export for the command line** (Settings >
Network) is the one place a key leaves the store, in a file locked with a
passphrase you choose (PBKDF2-HMAC-SHA256, 600,000 rounds, AES-256-GCM).

## Pinning the server

For every host that has a client certificate, the first server key VerbNest
sees is remembered (trust on first use). If the host later shows a different
key, the request is stopped before anything is sent and the message gives the
old and new key and their dates. A certificate renewed with the same key still
matches. Settings > Network > Pinned servers lists the pins; each can be
switched off or forgotten, and pinning can be switched off altogether.
Nothing is pinned when certificate checking is off or the certificate is not
trusted. WebSocket and SSE connections are not pinned.

You can also set the oldest TLS version to accept (1.2 or 1.3), and
**Test connection** shows the handshake (server certificate, trust, the client
certificate offered, pin state) without sending a request.

## Keys held by the system

On macOS, iOS and Android, **Add from the system keystore** (Settings >
Network) uses a certificate whose key stays in the Keychain or the Android
KeyStore. VerbNest never reads that key: it opens a connection inside the app
to the platform's TLS, which signs with the key and carries the bytes. Pick the
identity, say which hosts get it, or import a PKCS#12 file into the keystore
(the system keeps the key and VerbNest keeps only the identity's id). On
Android you can also choose from the credentials installed in the system
settings.

- The identity can be unlocked by the system (a password, Touch ID or a smart
  card prompt) each time it is used.
- Such an entry is not in the export file and the command line cannot use it
  (it prints a warning and skips it); it does not work through a proxy yet.
- If the identity is removed from the keystore, requests say so and the entry
  has to be chosen again.

## Limits

- `dart:io` does not say which TLS version or cipher was negotiated, nor
  whether the server asked for or accepted the client certificate. When a
  server closes the connection right after the handshake, VerbNest says it
  probably needs a certificate.
- Keys held by the system are supported on macOS, iOS and Android (see
  below); smart cards only through what the system exposes as a Keychain
  identity. Linux and Windows are not enabled yet.

## Command line and CI

See [cli-client-certificates.md](cli-client-certificates.md).
