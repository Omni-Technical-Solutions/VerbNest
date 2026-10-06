# ADR-002: QuickJS-ng as the single script engine, through the `fjs` package

- **Status:** Accepted for macOS, iOS and Android (spike passed). Windows and Linux are not yet proven; they are covered by the CI matrix, which has not run.

## Decision
Scripts (FR-SCR-*) run in QuickJS through the `fjs` Flutter package (a Rust wrapper around QuickJS). One engine on every platform, so scripts behave the same everywhere. The decision was made by the owner after comparing:

- `fjs`: has a memory limit, a stack limit, and `engine.close()` interrupts a script that never returns (this is how Verbnest enforces the 5 s timeout). Host modules (fs, net, fetch, process) are opt-in, and Verbnest enables none. Cost: builds on Android, Windows and Linux need a Rust toolchain (`rustup`, plus the Android targets). Apple targets use signed prebuilt binaries.
- `quickjs_engine` (QuickJS-ng 0.14, plain C): builds without Rust, but exposes no interrupt handler, so an infinite loop cannot be stopped. Rejected.

## Consequences
- `ScriptEngine` is an interface in the app (`lib/src/scripting`). Widget tests use a fake; the real engine is tested by `integration_test/script_test.dart` on a device or desktop.
- A fresh engine is created per script run (median 3 ms on macOS, 16 ms on the Android x86_64 emulator), so scripts cannot leak state into each other.
- The `pm` API and a Chai subset are written in JavaScript (`prelude.dart`) and run inside the sandbox. Unsupported APIs throw a "not supported" error that names the API.
- Not proven: Windows and Linux builds, arm64 Android on a real device, the supply chain of a young third-party package (pin the version and review upgrades).

## Spike results (v0.19.0)
| Platform | Result |
|---|---|
| macOS (Intel, debug) | pass: tests, timeout, memory cap, sandbox |
| iOS 18 simulator | pass |
| Android x86_64 emulator (needs Rust + Android targets) | pass |
| Windows, Linux | not run |
