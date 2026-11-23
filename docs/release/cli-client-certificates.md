# Client certificates on the command line and in CI

`verbnest run` can send your client certificate, trust extra CAs and use the
proxy you set up in the app. Nothing here changes what the app does.

## Files on the command line

```sh
verbnest run my.verbnest -c "Orders API" \
  --cert client.pem --key client.key --cert-host "api.example.com" \
  --cert-passphrase-env KEY_PASS --ca corp-root.pem
```

- `--cert` is a PEM certificate (give `--key` too) or a PKCS#12 bundle (`.p12`,
  `.pfx`). `--cert-host` says which hosts get it: `api.example.com`,
  `*.example.com` or `*` (the default), with an optional `:port`.
- A key or bundle with a passphrase: `--cert-passphrase-env VAR` (the name of
  an environment variable) or `--cert-passphrase-file file` (first line). There
  is no option for typing it on the command line: it would show in `ps`.
- `--ca file` trusts another CA (repeat for several).
- `--insecure` skips verification of the server certificate as before.

Every file is checked first. A wrong passphrase, a key that does not match, or
a file that is not a certificate stops the run with exit code 2 and says why.
An expired certificate prints a warning and the run goes on.

## What you set up in the app

On the machine where the app is installed:

```sh
verbnest run my.verbnest -c "Orders API" --app-network --vault
```

`--app-network` reads this workspace's proxy, CAs and client certificates from
the app's data folder (`--app-data-dir dir` if it is somewhere unusual). The
private keys and passphrases are in the system secret store, so add `--vault`;
without it an entry that needs its key is reported and left out.

The Mac App Store version of the app keeps its data and secrets in a sandbox
that a command-line tool cannot open. Use the export below.

## For CI, or the Mac App Store app: the export file

In the app, **Settings > Network > Export for the command line** writes
`verbnest-network.json`: your proxy, CAs, client certificates and keys, locked
with a passphrase you type (PBKDF2-HMAC-SHA256, 600,000 rounds, AES-256-GCM).
Keep the file and the passphrase apart, for example the file in the repository
or a CI secret file and the passphrase in a CI secret:

```sh
export VERBNEST_NET_PASS=...        # from the CI secret store
verbnest run my.verbnest -c "Orders API" \
  --network-config verbnest-network.json \
  --network-config-passphrase-env VERBNEST_NET_PASS
```

A wrong passphrase or a changed file is refused. Anyone who has both the file
and the passphrase has your keys: treat them like the keys themselves.

## Looking at certificates and servers

```sh
verbnest tls inspect client.pem --key client.key   # what it says, and that the key fits
verbnest tls inspect bundle.p12 --passphrase-env KEY_PASS
verbnest tls check https://api.example.com --cert client.pem --key client.key
```

`tls check` does the TLS handshake and sends no request. It prints the server
certificate, whether it is trusted and names the host, and the client
certificate that was offered. Exit code 0 is fine, 1 means the handshake failed
or the server closed the connection right after it (the usual sign that it
wanted a client certificate and was not given an acceptable one), 2 means a
file could not be read. With `--strict`, an untrusted or wrongly named server
certificate is exit code 1 as well.

## What the output never contains

The run report (JSON, JUnit, HTML) and the console never show a key, a
passphrase or certificate text. `verbnest run` prints one line per source to
stderr, for example `TLS: client certificate client.pem for *`.
