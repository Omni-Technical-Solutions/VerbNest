# ADR-004: Riverpod for app state; plain Dart models

- **Status:** Accepted (amends the original "Riverpod + freezed")

## Decision
Use `flutter_riverpod` for app state. Domain models live in pure-Dart packages as hand-written immutable classes with `copyWith` and JSON methods; `freezed`/code generation is not used.

## Why
Hand-written models keep the core packages free of build_runner and make unknown-key preservation (`HttpRequestItem.extra`) explicit. The model count is small. Revisit if the number of models makes the boilerplate costly.
