# ADR-008: HTTP/2 through the `http2` package

- **Status:** Accepted (implemented in `verbnest_http`, v0.26.0)

## Context
ADR-001 left HTTP/2 open. Many APIs now serve HTTP/2 only on some routes, and users expect the protocol to show in the response. HTTP/2 frames, HPACK and flow control are too large to write by hand.

## Decision
- Use the `http2` package (dart-lang, pure Dart) for framing, HPACK and flow control. The engine keeps owning sockets, TLS, proxies, cookies, redirects, timeouts and cancel.
- Negotiate through ALPN on the TLS socket. Setting `httpVersion` per request: `auto` (offer `h2` and `http/1.1`, default), `1.1`, or `2` (offer only `h2`, fail clearly if refused).
- No `h2c` (HTTP/2 over plain text) and no upgrade from HTTP/1.1. `2` with an `http://` URL is an error.
- One connection per exchange, as before. Connection reuse stays a later optimisation; it would need a pool shared by HTTP/1.1 and HTTP/2.
- The "sent" view shows the pseudo-headers and lower-case fields as encoded (`GET /path HTTP/2`, `:authority: …`). This is not wire bytes: HPACK output is not text. Header order and values are kept; names are lower case because HTTP/2 requires it. Connection-specific headers (`Connection`, `Keep-Alive`, `Transfer-Encoding`, `Upgrade`, `Host`) are dropped, and `Host` becomes `:authority`.
- Trailers are read and ignored. Server push is off.

## Consequences
- Constitution V (wire fidelity) holds for header values and order, not for the exact bytes. This is stated in the UI by the `HTTP/2` label and in this ADR.
- Proxies keep working because HTTP/2 starts after the CONNECT tunnel or SOCKS5 handshake.
- Tested against a local h2 server (`test_server/lib/h2_server.dart`) and by hand against `nghttp2.org` and `cloudflare.com`.
- The package stalls on one large `DATA` message once the peer's flow-control window is used. Our test server therefore sends frame-sized pieces. The client reads incrementally and was not affected by real servers.
