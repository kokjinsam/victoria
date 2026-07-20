# Glossary

- **Conformance** — agreement between a formal trace and an implementation across all verified states.
- **Verification** — exact comparison of one expected state with one observed state.
- **Expected state** — the state described by the formal trace.
- **Observed state** — the state reported by the implementation.
- **Runner** — the participant that replays a formal trace against an implementation.
- **Verifier** — the participant that compares expected and observed states.
- **Spec** — a validated reference to one TLA+ source artifact and its optional configuration artifact.
- **Apalache plan** — a non-executing description of a future Apalache operation.
- **Apalache execution** — synchronous execution of an existing Apalache plan without implementation
  verification.
- **Trace materialization** — discovery of generated top-level ITF files and all-or-nothing conversion of
  every discovered file into validated Victoria traces.
- **Supported Apalache version** — the exact Apalache release validated by the current Victoria release;
  Phase 1.2 supports v0.58.3.
- **Run directory** — the exclusively reserved location assigned to one Apalache operation; its artifacts
  survive successful and failed materialization.
- **Run manifest** — the `victoria-run.json` document recording the plan, execution context, artifacts, and
  outcome of one Apalache operation.
- **Running manifest** — the initial run manifest committed before Apalache starts, showing that the run was
  reserved but has not reached a materialized or failed outcome.
- **Completed manifest** — the final run manifest written after execution and trace materialization finish.
- **Materialized outcome** — a completed manifest outcome showing that one or more generated traces were
  discovered and all were loaded successfully, regardless of Apalache's exit status.
- **Orphaned run** — a retained run directory whose manifest remains `running` because its owner did not
  complete the final manifest replacement.
- **Atomic manifest replacement** — writing a complete temporary manifest and renaming it over the prior
  manifest so observers never see partially written JSON; this is not a power-loss durability guarantee.
- **Successful materialization** — a terminated Apalache process that produced one or more valid traces,
  regardless of its raw exit status.
- **Apalache result** — complete execution context with plural, lexically ordered trace paths and their
  positionally corresponding validated traces.
- **Conformance workflow** — a high-level operation that allocates an Apalache run, materializes formal
  traces, and verifies those traces against an implementation model.
- **Workflow verification** — the result of verifying one generated trace through an independent
  implementation lifecycle.
- **Stop-first verification** — sequential verification that terminates after the first trace that does not
  conform.
- **Completed verification** — a successful verification report produced before a later trace failed.
- **Workflow success** — an Apalache run materialized one or more traces and every materialized trace
  conformed. The workflow does not deduplicate traces, every trace starts a fresh implementation lifecycle,
  lower-level APIs remain independently usable, and no workflow-level durable manifest exists yet.
- **Generated conformance assertion** — `Victoria.ExUnit.assert_conform/3` runs a complete generated
  conformance workflow from a validated Spec and raises `ExUnit.AssertionError` when controlled Apalache,
  trace-materialization, or implementation-verification failures occur. `assert_conform/2` remains the
  fixed-trace form. Both plain functions return only `:ok` on success and preserve programmer misuse as
  `ArgumentError`; callers needing `%Victoria.Workflow.Result{}` use `Victoria.Workflow.run/3` directly.
