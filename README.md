# Verbnest Spec Kit

Verbnest is an open source, local-first API client in the spirit of Postman, built with Flutter for **Android, iOS, Linux, macOS and Windows**. It lets developers compose, send, organise, script and test HTTP/REST, GraphQL, WebSocket, SSE, gRPC and other remote function call (RPC) traffic, without requiring an account or a cloud service.

This kit is organised in the spirit of GitHub's spec-kit: principles first, then *what* to build, then *how*, then *in what order*.

| # | File | What it answers |
|---|------|-----------------|
| 1 | [constitution.md](docs/spec/constitution.md) | Non-negotiable principles every decision is checked against |
| 2 | [feature-inventory.md](docs/spec/feature-inventory.md) | Postman's feature set reviewed, mapped to Verbnest with MVP / v1 / later priority |
| 3 | [requirements.md](docs/spec/requirements.md) | Functional requirements (FR-xxx) and non-functional requirements (NFR-xxx) with acceptance criteria |
| 4 | [architecture.md](docs/spec/architecture.md) | Layered architecture, tech stack, Flutter packages, per-platform constraints |
| 5 | [data-model.md](docs/spec/data-model.md) | Entities, on-disk file format, database schema, variable resolution rules |
| 6 | [ux.md](docs/spec/ux.md) | Information architecture, responsive layouts for phone / tablet / desktop, key flows |
| 7 | [testing.md](docs/spec/testing.md) | Test strategy, test matrix per platform, fixtures, CI |
| 8 | [roadmap.md](docs/spec/roadmap.md) | Phased delivery plan with milestones and exit criteria |
| 9 | [open-questions.md](docs/spec/open-questions.md) | Decisions deliberately left open, with a recommended default for each |

## One-paragraph pitch

Postman became the default API tool, then moved toward mandatory cloud accounts, workspaces in the vendor's cloud and per-seat pricing. Some of us are more comfortable with local-first, git-friendly alternatives, but none is a native-feeling, single-codebase app that also runs on **phones and tablets**. Verbnest's wedge is: *every protocol you test, on every device you own, stored in a single portable SQLite file, with lossless export to Postman and git-friendly YAML.*

## Scope in one line per phase

- **MVP (Phase 1):** HTTP/REST requests, collections & folders, environments & variables, common auth, history, cURL + Postman v2.1 import, response viewer, SQLite workspace storage. All five platforms.
- **v1 (Phases 2–3):** Pre-request/test scripts (JavaScript), collection runner, GraphQL, WebSocket, SSE, OpenAPI import, code generation, cookies, certificates, proxy, YAML snapshot export/import for git.
- **Later (Phase 4+):** gRPC, MQTT, Socket.IO, JSON-RPC/XML-RPC/SOAP, local mock server, CLI runner, plugins, monitors-lite, optional self-hosted sync.

## Conventions used in this kit

- **MUST / SHOULD / MAY** follow RFC 2119.
- Priorities: **P0** = MVP, **P1** = v1, **P2** = later, **—** = explicitly out of scope.
- Requirement IDs (`FR-HTTP-003`) are stable; reference them in issues and PRs.
