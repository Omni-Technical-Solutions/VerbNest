# ADR-005: No Flutter web target

- **Status:** Accepted

## Decision
VerbNest targets Android, iOS, macOS, Windows and Linux only.

## Why
Browsers enforce CORS and forbid setting some headers, which would make a web build misleading as an API client (see open-questions #4). Raw sockets are also unavailable on web.
