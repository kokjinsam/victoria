# Changelog

All notable changes to Victoria will be documented in this file.

## [Unreleased]

## [0.1.0] — Unreleased

Initial public release.

### Added

- Strict loading and validation of Apalache ITF traces.
- Fixed-trace conformance verification.
- Opaque implementation lifecycle through `Victoria.Model`.
- Sequential replay with initialization, cleanup, and structured failures.
- Exact expected/observed state verification.
- ExUnit assertions for fixed traces.
- TLA+ specification and Apalache invocation planning.
- Shell-free Apalache v0.58.3 execution.
- Deterministic trace discovery and materialization.
- Versioned Apalache run lifecycle manifests.
- Generated conformance workflow orchestration.
- ExUnit assertions for generated workflows.

### Known limitations

- Only Apalache v0.58.3 is supported.
- Apalache execution is synchronous and has no Victoria timeout.
- Cancellation and caller-death handling are not implemented.
- Lasso traces can be materialized but cannot be replayed.
- ITF tagged-value support is intentionally partial.
- State comparison uses exact Elixir `===`.
- Generated traces are verified sequentially.
- Generated verification stops on the first failing trace.
- Apalache run artifacts are retained automatically.
- Public APIs may change during the `0.x` series.

[Unreleased]: https://github.com/kokjinsam/victoria/compare/v0.1.0...HEAD
[0.1.0]: https://github.com/kokjinsam/victoria/releases/tag/v0.1.0
