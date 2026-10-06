# ADR-009: Where GraphQL, WebSocket/SSE and the CLI live, and in what order

- **Status:** Accepted

## Context
Three roadmap items touch the same code: GraphQL (Phase 3), WebSocket and SSE (Phase 3) and the headless CLI (Phase 5). Today the collection runner, request pipeline and script bridge live in `apps/verbnest_app` (`state/runner.dart`, `scripting/`), and the script engine uses `fjs`, a Flutter plugin. The CLI needs all of that without Flutter. If GraphQL or WebSocket logic were written in the app first, the CLI would force a move of that code later.

## Decision
Build in this order, and keep every new feature in a Flutter-free package from the first line.

1. **GraphQL.** A GraphQL request is an HTTP request. It adds a body mode, not a protocol.
   - Model (`GraphqlBody`: query, variables, operation name) in `verbnest_core`.
   - Building the JSON payload, introspection query, schema model and SDL import in `verbnest_core` / `verbnest_import` (pure Dart).
   - Sending uses `HttpEngine` unchanged, so the runner, scripts, cookies, proxy, HTTP/2 and history work without changes.
   - The app only adds the editor and schema explorer.
2. **WebSocket and SSE.** These are connections, not request/response pairs.
   - A `RealtimeConnection` interface (open, send, messages stream, close) and the two implementations live in `verbnest_http/lib/src/realtime/`, built on the same socket, TLS, proxy and cookie code as `HttpEngine` (WebSocket handshake by hand over `Socket`, like ADR-001, so headers and bytes stay under our control).
   - Saved messages are plain data in `verbnest_core`.
   - The runner skips real-time requests with a note; they are interactive.
   - The app only adds the message log UI.
3. **CLI.** After 1 and 2 are done.
   - First move the runner loop, request pipeline and `pm` bridge out of the app into a pure Dart package `verbnest_runner`, behind a `ScriptEngine` interface. The app keeps the `fjs` implementation.
   - Choosing the script engine for the CLI (an FFI QuickJS build usable from plain Dart, or no scripts in the first CLI release) is a separate decision and ADR.
   - Because 1 and 2 already sit in pure packages, this move touches only existing runner code.

## Consequences
- GraphQL and WebSocket need no refactor when the CLI arrives. Only the existing runner is moved.
- The CLI comes last because its blocker is the script engine, not the protocols.
- Rule for all new features: models and logic go in `verbnest_core`, `verbnest_http`, `verbnest_import`; `apps/verbnest_app` holds widgets and Riverpod glue only.

## Outcome (v0.29.0)

The runner loop now lives in `verbnest_runner` and the CLI in `verbnest_cli`. The CLI does not run scripts because `fjs` is a Flutter plugin; adding scripting to the CLI needs its own decision.
