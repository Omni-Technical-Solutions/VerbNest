# ADR-010: Scripts in the CLI through an external JavaScript runtime

Status: accepted (v0.32.0)

## Context

The app runs scripts in QuickJS through `fjs`, a Flutter plugin built with
Rust. A plain Dart program cannot import it, and `quickjs_engine` is also a
Flutter plugin. Building QuickJS ourselves for each OS and loading it through
`dart:ffi` would mean shipping and signing native libraries for the CLI.

## Decision

- Move the script contract, the `pm` prelude, the phase runner and the request
  mapping into a Flutter-free package, `verbnest_script`. The app keeps `fjs`
  behind the same `ScriptEngine` interface.
- The CLI runs `ScriptInput.toSource()` in an external runtime, `node` by
  default (`--js-runtime` to change it), inside a fresh `vm` context with no
  globals beyond the language built-ins, a wall-clock timeout, and a heap cap.
  The prelude defines everything scripts can touch, so the program is the same
  as in the app.
- Variables scripts set live in memory for the run; the CLI never writes the
  workspace file.

## Consequences

- Scripts in the CLI need Node on the machine. Without it they are skipped and
  named on stderr, as before.
- QuickJS and V8 differ in rare language edge cases, and error text can differ.
- Node's `vm` is not a security boundary. The CLI runs a workspace the user
  chose, with the same trust as running its requests.
- An embedded engine can replace `ProcessScriptEngine` later without touching
  the runner.
