# Architecture notes

## Request pipeline

Every request that is sent, from the app editor, the collection runner or
the CLI, is prepared by `prepareRequest` in
`packages/verbnest_runner/lib/src/request_pipeline.dart`. It inherits auth
from the containers above the request, swaps OAuth 2.0 auth for a bearer
token (the caller supplies how, because the app can sign in through a
browser and the CLI cannot), reads attachment files from the workspace and
builds the `PreparedRequest`.

Also in that file:

- `evaluateAssertions` runs a request's enabled assertions against a response.
- `requestErrorMessage` turns OAuth, build and engine failures into one
  user-facing message.
- `HistoryRecorder` (`history_recorder.dart`) writes masked history rows for
  both the app and the CLI.

Add new send paths on top of these; do not re-implement them.

## Packages

| Package | Owns |
|---|---|
| `verbnest_core` | Models, variables, GraphQL, JSON/XML tools. No I/O. |
| `verbnest_http` | The socket-level HTTP engine, proxies (`proxy_tunnel.dart`), TLS, OAuth, realtime. |
| `verbnest_storage` | Workspace SQLite file. `WorkspaceRepository` is the facade; attachments and search text live in `attachment_store.dart` and `search_documents.dart`. |
| `verbnest_import` | Postman, OpenAPI, HAR, cURL import. Shared JSON helpers are in `json_util.dart`. |
| `verbnest_script` | Script engine. |
| `verbnest_runner` | Request pipeline, headless runner, mock server. |
| `verbnest_cli` | Command line. |
| `apps/verbnest_app` | Flutter UI and Riverpod state. |

## Keeping complexity down

Run `python3 scripts/complexity_report.py` for the longest, branchiest and
deepest functions. Prefer splitting a long `build` into small widgets or
methods per section, and keep new functions under about 60 lines.

## Not done (refactor leftovers)
The JS prelude asset (the CLI is pure Dart with no asset bundle), the GraphQL lexer and completion splits and typed storage mappers remain. `mock_server_dialog.build`, `json_schema._check` and the cookie domain check are split. A CI function-size gate (scripts/complexity_report.py --check, limits 260 lines / 90 branches) now stops regressions.
