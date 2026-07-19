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
- **Successful materialization** — a terminated Apalache process that produced one or more valid traces,
  regardless of its raw exit status.
- **Apalache result** — complete execution context with plural, lexically ordered trace paths and their
  positionally corresponding validated traces.
