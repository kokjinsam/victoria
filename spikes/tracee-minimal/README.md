# Minimal Apalache 0.58.3 tracee compatibility probe

Two tiny models with one counter and two transitions:

- **TraceeMinimal.tla**: one state variable (count). The pure operator Double = 2 * count does not appear in the emitted ITF state; it would require trace evaluation.
- **EmbeddedMinimal.tla**: carries expectedDouble as an additional state variable and updates it in Init and Next. Its actual generated ITF contains [0, 2, 4].

GitHub Actions simulates both with real Apalache 0.58.3, validates generated ITF values, then separately tries the documented tracee --trace=ITF --expressions=Double source.tla invocation and a positional alternative.

A green experiment means **we classified the actual behavior**, not that tracee passed.

## Source-level discrepancy in v0.58.3

[TraceeCmd.scala](https://github.com/apalache-mc/apalache/blob/v0.58.3/mod-tool/src/main/scala/at/forsyte/apalache/tla/tooling/opt/TraceeCmd.scala) reads trace length in run() from options.input.source. [AbstractCheckerCmd](https://github.com/apalache-mc/apalache/blob/v0.58.3/mod-tool/src/main/scala/at/forsyte/apalache/tla/tooling/opt/AbstractCheckerCmd.scala) populates input.source with the specification file. TraceeCmd.toConfig separately populates tracee.trace with the ITF. Thus the normal documented invocation attempts to read the TLA+ source as a JSON trace.

Supplying the ITF as the normal source creates a different issue: the source parser needs a TLA+ or Apalache specification, not ITF.

This spike does not patch Apalache, touch Victoria core logic, or claim tracee works. It establishes observable behavior of the pinned release and compares it with the direct-ITF fallback.

## Usability interpretation

Embedded variables work with the current Apalache output and Rust ITF reader, at the cost of an additional state variable and update logic. Pure projection operators make the model smaller but need a functional trace evaluator. Neither is declared Victoria's final convention.
