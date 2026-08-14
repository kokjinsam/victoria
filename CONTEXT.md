# Glossary

- **Conformance** — agreement between a formal trace and an implementation across all verified states.
- **Verification** — exact comparison of one expected state with one observed state.
- **Expected state** — the state described by the formal trace.
- **Observed state** — the state reported by the implementation.
- **Runner** — the participant that replays a formal trace against an implementation.
- **Verifier** — the participant that compares expected and observed states.
- **Spec** — a validated reference to one TLA+ source artifact and its optional configuration artifact.
- **Apalache plan** — a non-executing description of a future Apalache operation.
- **Apalache execution** — synchronous execution of an existing Apalache plan by Apalachex, without Victoria
  implementation verification.
- **Artifact materialization** — Apalachex discovery of generated top-level ITF files, recorded independently
  of whether Victoria can decode them.
- **Trace loading** — ordered, all-or-nothing decoding of every Apalachex ITF path by the standalone ITF
  package and semantic adaptation into Victoria traces for replay.
- **Supported Apalache version** — the exact Apalache release validated by the current Victoria release;
  Victoria 0.2.0 supports v0.58.3.
- **Run directory** — the location exclusively reserved by Apalachex for one operation; its artifacts survive
  successful and failed materialization.
- **Run manifest** — the Apalachex-owned `apalachex-run.json` document recording the plan, execution context,
  artifacts, and outcome of one Apalache operation. Victoria writes no second manifest.
- **Running manifest** — the initial run manifest committed before Apalache starts, showing that the run was
  reserved but has not reached a materialized or failed outcome.
- **Completed manifest** — the final run manifest written after execution and artifact materialization finish.
- **Materialized outcome** — a completed Apalachex manifest outcome showing that one or more ITF artifacts
  were discovered, regardless of Apalache's exit status or later Victoria decoding and verification.
- **Orphaned run** — a retained run directory whose manifest remains `running` because its owner did not
  complete the final manifest replacement.
- **Atomic manifest replacement** — writing a complete temporary manifest and renaming it over the prior
  manifest so observers never see partially written JSON; this is not a power-loss durability guarantee.
- **Successful materialization** — a terminated Apalache process for which Apalachex found one or more ITF
  artifacts, regardless of raw exit status or whether Victoria later accepts their contents.
- **Apalache result** — an `Apalachex.Result` with complete execution context and ordered `itf_paths`.
  It does not contain Victoria traces.
- **Conformance workflow** — a high-level operation that allocates an Apalache run, loads its materialized
  artifacts as formal traces, and verifies those traces against an implementation model.
- **Workflow verification** — the result of verifying one generated trace through an independent
  implementation lifecycle.
- **Stop-first verification** — sequential verification that terminates after the first trace that does not
  conform.
- **Completed verification** — a successful verification report produced before a later trace failed.
- **Workflow success** — an Apalache run materialized one or more ITF artifacts, Victoria loaded them as
  traces, and every trace conformed. The workflow does not deduplicate traces, every trace starts a fresh
  implementation lifecycle, direct Apalachex lower-level APIs remain independently usable, and no workflow-level durable
  manifest exists.
- **Generated conformance assertion** — `Victoria.ExUnit.assert_conform/3` runs a complete generated
  conformance workflow from a validated Spec and raises `ExUnit.AssertionError` when controlled Apalache,
  trace-loading, or implementation-verification failures occur. `assert_conform/2` remains the
  fixed-trace form. Both plain functions return only `:ok` on success and preserve programmer misuse as
  `ArgumentError`; callers needing `%Victoria.Workflow.Result{}` use `Victoria.Workflow.run/3` directly.
