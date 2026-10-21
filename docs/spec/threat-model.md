# Threat model (0.65)

Plan phase F2 of `docs/spec/security-and-complexity-plan.md`. It lists what VerbNest protects, who or what it must be protected from, the places where untrusted data enters, and what is done about each. It is a working document: change it when a feature changes a trust boundary.

## 1. What is protected
| Asset | Where it lives | Why it matters |
| --- | --- | --- |
| Secret variable values (tokens, passwords, API keys) | The OS keychain or keystore (`VaultSecretStore`); never in the workspace file | Account takeover if leaked |
| Workspaces: collections, requests, environments (non-secret values), examples | One SQLite file on the device | Reveals internal APIs and data |
| History and the console: URLs, headers, bodies | Local SQLite (history, optional bodies) and memory (console) | Bodies can hold tokens and personal data |
| OAuth tokens | Memory and the secret store | Same as secrets |
| The user's machine and network position | The device | A client that runs scripts and opens connections can be turned against it |

VerbNest has no account, no server and no telemetry, so there is nothing of ours to attack remotely: the threats come through the data the user opens or the servers the user calls.

## 2. Who or what is untrusted
1. **A server the user calls**: every byte of every response (status line, headers, chunking, compression, body, cookies, redirects, TLS certificate).
2. **Files the user opens**: Postman, OpenAPI, HAR and cURL imports, workspace snapshots, data files for the runner, `.verbnest` workspace files received from someone else.
3. **Scripts inside an imported collection** (JavaScript).
4. **Other software on the same device or network**: other local processes (the OAuth loopback port, the mock server), web pages in the user's browser (DNS rebinding against the mock), someone with a copy of the device backup.
5. **The supply chain**: Dart and Rust dependencies, the build and release process, GitHub Actions.

Not in scope: a user who already controls the device (rooted or jailbroken, malware with the user's rights), and the correctness of the servers being tested.

## 3. Entry points and what is done
| Entry point | Abuse | Defence | Tests | Residual risk |
| --- | --- | --- | --- | --- |
| HTTP response parsing (`response_reader.dart`) | Malformed or huge framing, decompression bomb | Cap 256 MB desktop / 64 MB mobile, also after decompression and per chunk; every parse failure is an engine error | `fuzz_test.dart` (http), `body_limit_test.dart` | A body near the cap still takes memory; a "save to file" path for larger bodies is not built |
| Redirects (`redirects.dart`) | Credential theft by redirecting to another host, downgrade | Authorization, Proxy-Authorization and Cookie never cross an origin, custom headers only if on a safe list; scheme or port change is another origin | `redirects_test.dart` | A same-origin redirect keeps credentials by design |
| TLS | Interception | Verification on by default; turning it off is per request or workspace and the CLI warns; custom CAs and client certificates are explicit | engine and network tests | A user who turns verification off is exposed |
| Cookies | Cookie injection, cross-site leakage | Jar scoping by domain, path and secure; invalid cookies ignored | cookie tests, `fuzz_test.dart` (core) | Public-suffix handling is basic |
| Response preview (HTML, PDF, images) | Script or resource loading, parser bugs | HTML renderer has no scripting and swallows taps; PDFium runs in-process (kept current, size not capped separately) | widget tests | A memory-safety bug in PDFium would run in the app process |
| Imports (Postman, OpenAPI, HAR, cURL, snapshots, data files) | Crafted files: deep nesting, YAML anchors, huge files, path traversal on write | 64 MB cap, YAML node and depth limits, only `FormatException` leaves a parser, snapshot paths checked (no `..`, absolute, symlink escape) | importer fuzz test, core fuzz test, snapshot tests | New formats need the same checks |
| Scripts in the app (QuickJS via `fjs`) | Code from a collection reads secrets, files or the network | Off until the workspace is trusted; engine has no host modules; 64 MB, 512 KB stack, 5 s; secret variables are not given to scripts | script tests | The embedded engine and its Rust crates are scanned weekly; six advisories in its unused fetch stack are ignored until 2026-12-31 |
| Scripts in the CLI (Node) | `node:vm` is not a boundary | Scripts run only with Node's permission model, else `--unsafe-node-scripts` is required | `process_engine_test.dart` | A trusted-but-malicious script under `--unsafe-node-scripts` |
| OAuth browser sign-in | Another local process or page captures the code | PKCE (S256), random `state`, loopback-only receiver, one use | OAuth tests | A local process running as the user can still read memory |
| Mock server | A web page reads the mock via DNS rebinding | Loopback bind, `Host` must be a loopback name, request size limit | mock server tests | Binding to a non-loopback address is the user's choice |
| Local storage | Reading the workspace or history file | Secrets are not in the file; history bodies off by default on phones and tablets; Android backup and device transfer off | `android_manifest_test.dart`, `history_defaults_test.dart` | The workspace and history are not encrypted at rest; protect the device |
| Logs, console, exports | Secrets in output | Values are masked in the console, history, run reports and code generation; secret hosts must be approved before a secret is sent | masking tests | A secret in a header name or a response body is not masked |
| Build and release | A tampered dependency or workflow | Lockfile, Dependabot and security updates, pinned action SHAs, pinned and checked tool binaries, gitleaks and osv-scanner in CI, DCO, protected `main`, notarised and signed releases | CI | Maintainer account compromise; keep two-factor on |

## 4. Abuse cases worth testing by hand
- Open a collection from an untrusted source with scripts and run it: nothing should run until the workspace is trusted, and a script must not read secret variables.
- Call a server that redirects from `https://a` to `http://b` to `https://c`: no credential should arrive at b or c.
- Call a server that returns a 1 GB body, a gzip bomb, an endless chunked stream, an endless header: the app should stop with a clear error and stay responsive.
- Import a Postman collection and a YAML file with deep nesting and many anchors: rejected, not frozen.
- Export a snapshot and import it into an existing folder with a symlink: nothing written outside the folder.
- Check the Android app with `adb backup` / `bmgr` and the iOS device backup: no workspace data.

## 5. Open items
- A "save to file" path for responses above the cap (S4 follow-up).
- Optional encryption of the history table.
- Fuzz the HTTP/2 frame reader and the WebSocket frame reader (the HTTP/1 reader, importers and core parsers are fuzzed).
- Done (S7): verified on an Android 15 emulator that `http://` requests work without `usesCleartextTraffic`; the flag is removed.
- An external review before 1.0.
