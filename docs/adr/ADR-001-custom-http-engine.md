# ADR-001: Custom HTTP engine over `dart:io` sockets

- **Status:** Accepted (implemented in `postit_http`, v0.1+)

## Context
An API client must control what goes on the wire: header order and casing, raw bodies, redirect handling and the exact bytes sent. `HttpClient` normalises headers and hides the sent request; native stacks differ per platform.

## Decision
Implement HTTP/1.1 over `dart:io` `Socket`/`SecureSocket` in pure Dart (`HttpEngine`). One connection per exchange (`Connection: close`) for now.

## Consequences
- Identical behaviour on all five platforms; the "sent" view shows the real bytes.
- We own chunked decoding, gzip/deflate, redirects, timeouts and cancellation, all covered by tests against a local raw-socket test server.
- Not yet done: HTTP/2, connection pooling, proxies, client certificates. Add when needed; the `HttpEngine.send` contract does not change.
