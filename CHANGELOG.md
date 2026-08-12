# Changelog

All notable changes to Victoria will be documented in this file.

## [Unreleased]

### Changed

- Made the root Justfile the public development and CI command interface, with a repository-complete pinned
  asdf toolchain and owned asdf provisioning for Apalache 0.58.3.
- Delegated ITF file reading and format decoding to the standalone ITF 0.1.x package while retaining
  Victoria's trace adaptation, replay semantics, and public error boundary.
- Accepted standalone ITF rich value structs unchanged in replay states.
- Adopted ITF's default input-size and nesting-depth limits, decoded metadata behavior, and upstream
  reason/path terminology where legacy decoder details cannot be reconstructed without decoding twice.
- Replaced Victoria's duplicate Apalache executor with Apalachex 0.1.0 while preserving Victoria trace
  decoding, verification, model lifecycle, result, workflow, and ExUnit contracts.
- Made `apalachex-run.json` the sole execution and artifact manifest. Its `materialized` outcome records
  discovered ITF artifacts and remains valid if Victoria later rejects an ITF during decoding.
- Preserved upstream Apalachex execution and specification errors intact in workflow failures.
- Removed the low-level `Victoria.Apalache` modules in favor of direct Apalachex 0.1.x composition.
- Changed `Victoria.Spec.new/1` to return `Apalachex.Spec` and preserve `Apalachex.Spec.Error`.
- Changed workflow result and error `apalache` fields to `Apalachex.Result`, with ordered `itf_paths` and no
  loaded `traces` field.
- Removed `Victoria.ITF`. `Victoria.Trace.load/1` now preserves generic `ITF.Error` values and returns
  `Victoria.Trace.Error` only for Victoria adaptation failures.

## [0.1.0] — 2026-07-20

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
- State comparison uses exact Elixir `===`.
- Generated traces are verified sequentially.
- Generated verification stops on the first failing trace.
- Apalache run artifacts are retained automatically.
- Public APIs may change during the `0.x` series.

[Unreleased]: https://github.com/kokjinsam/victoria/compare/v0.1.0...HEAD
[0.1.0]: https://github.com/kokjinsam/victoria/releases/tag/v0.1.0
