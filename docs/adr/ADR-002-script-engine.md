# ADR-002: QuickJS-ng via FFI as the single script engine

- **Status:** Proposed. The Phase 0 spike (build on all five platforms) has not been run.

## Decision
Scripts (FR-SCR-*) run in QuickJS-ng through FFI, with one engine on every platform so scripts behave the same everywhere.

## Consequences
- Scripts are stored today (`Scripts`, Postman events) but never executed.
- Before accepting: prove the native build on Android, iOS, macOS, Windows and Linux, and measure start-up cost. If any platform fails, revisit.
