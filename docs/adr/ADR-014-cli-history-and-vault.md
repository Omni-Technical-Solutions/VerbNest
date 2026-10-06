# ADR-014: CLI history and vault secrets

Status: accepted (v0.42.0). Reverses the "not planned" note in the remaining-work plan.

## Decision

- `verbnest run --history <db>` (or `VERBNEST_HISTORY_DB`) records each sent request
  in a `LocalStore` database through `HistoryRecorder` (`verbnest_runner`). Rows
  have the same shape as the app's and secrets are masked first. The CLI never
  writes to the app's own database unless the user points it there; the default
  is no recording.
- `verbnest history <workspace> --db <db>` lists, shows (`--show id`), searches
  (`-q`) and clears (`--clear`) the rows of that workspace.
- `verbnest run --vault` reads the secrets the app saved, through
  `SystemSecretVault` over `VaultSecretStore`: `security` on macOS,
  `secret-tool` on Linux. The CLI never writes secrets. `--var` and
  `VERBNEST_VAR_<name>` still win.

## Limits

- macOS asks the user to allow `security` to read an item the app created. The
  first read shows that prompt, so `--vault` is for interactive use; CI should
  use `--var`.
- Linux reads the `account` attribute `flutter_secure_storage` sets. It is not
  covered by a test against a real keyring.
- Windows has no command-line reader for Credential Manager values; `--vault`
  exits 2 with a message that points to `--var`.
- Response bodies in history are stored as received (as in the app); only the
  request is masked.
