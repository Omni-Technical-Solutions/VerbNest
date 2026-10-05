# ADR-012: `pm.sendRequest` and `pm.cookies` by replay

Status: accepted (v0.39.0)

## Context

Scripts run as one synchronous JavaScript program that returns a JSON string
(ADR-002, ADR-010). Neither QuickJS through `fjs` nor the external runtime used
by the CLI is wired for a script to wait on a host call. `pm.sendRequest(req,
callback)` needs the response before the callback runs.

## Decision

- **Replay.** The prelude counts `pm.sendRequest` calls. A call that already
  has an answer in `ScriptInput.sendResults` runs its callback at once. The
  first call without an answer records the request in `ScriptOutput.needs`
  and unwinds the script. `runScriptPhaseWith` asks a `ScriptHost` to send it,
  adds the answer, and runs the script again from the start. Each request is
  sent once; tests, logs and variable changes from unfinished passes are
  dropped.
- **No engine changes.** Both engines already return one JSON string, so
  `needs` is one more field. The same code serves the app and the CLI.
- **Limits.** At most 10 requests per script and 60 s in all; each pass keeps
  the 5 s script timeout. Only `http` and `https`, raw and urlencoded bodies.
- **Host.** `EngineScriptHost` sends through the app's or the runner's
  `HttpEngine`, so requests share its cookie jar, proxy and certificates. They
  do not run scripts and are not written to history.
- **Cookies.** `pm.cookies.get/has/toObject` read what the jar would send to
  the request URL, taken before each pass. The CLI has no jar, so they are
  empty there. `pm.cookies.jar()` is not supported.

## Consequences

- Scripts should behave the same on every pass. `Date.now()` or random values
  can differ between passes; only the last pass counts.
- The callback runs inside the script body, not after it as in Postman. Code
  that depends on the callback running later can see a different order.
- A script that catches the unwinding error is still answered, because the
  pending request is checked after the script ends.
- Promises and `await pm.sendRequest` are not supported.
