# Victoria

Victoria connects formal TLA+ execution traces to concrete Elixir implementations. It can replay committed
ITF traces or invoke Apalache to generate traces and verify an implementation against every generated
behavior.

## Status

Victoria 0.1.0 is experimental. The two core workflows are usable, but public APIs may change during the
`0.x` series and Apalache compatibility is intentionally narrow.

## Installation

Add Victoria to `mix.exs`:

```elixir
def deps do
  [
    {:victoria, "~> 0.1.0"}
  ]
end
```

## Requirements

Fixed-trace verification requires Elixir 1.18 or later and does not require Apalache.

Generated workflows require Elixir 1.18 or later, Apalache exactly v0.58.3, and Apalache's Java and solver
runtime prerequisites on the test process's `PATH`. Victoria's release-readiness CI runs on Ubuntu. Other
operating systems are not release-tested and Windows support is not claimed.

## Model callback contract

A model owns the lifecycle of the implementation being checked:

```elixir
defmodule Counter.Model do
  @behaviour Victoria.Model

  @impl true
  def init(%{"count" => count}), do: Agent.start_link(fn -> count end)

  @impl true
  def execute(%Victoria.Step{action: "Increment"}, counter) do
    Agent.update(counter, &(&1 + 1))
    {:ok, counter}
  end

  def execute(%Victoria.Step{action: "Decrement"}, counter) do
    Agent.update(counter, &(&1 - 1))
    {:ok, counter}
  end

  @impl true
  def snapshot(counter), do: %{"count" => Agent.get(counter, & &1)}

  @impl true
  def project(%Victoria.Step{state: state}), do: state

  @impl true
  def cleanup(counter), do: Agent.stop(counter)
end
```

The `impl` returned by `init/1` and threaded through `execute/2` is an opaque implementation value owned by
the model. It may be a value, PID, database context, client, or another implementation handle.

- `init/1` creates the implementation from formal state zero.
- `execute/2` applies each later formal action and returns the next implementation handle.
- `snapshot/1` returns the implementation's observed state.
- `project/1` returns the formal step's expected state.
- Optional `cleanup/1` releases resources once after successful initialization on every controlled exit.

State zero is initialized and verified but never executed.

## Fixed-trace verification

Load a committed ITF trace and verify it programmatically:

```elixir
{:ok, trace} = Victoria.Trace.load("test/traces/counter.itf.json")
{:ok, report} = Victoria.verify(Counter.Model, trace: trace)

# A path may be supplied directly too.
{:ok, report} = Victoria.verify(Counter.Model, trace: "test/traces/counter.itf.json")
```

Or use the ExUnit assertion:

```elixir
import Victoria.ExUnit

:ok = assert_conform(Counter.Model, trace: "test/traces/counter.itf.json")
```

`Victoria.verify/2` returns a `Victoria.Runner.Report` on success, `Victoria.ITF.Error` when loading fails,
or `Victoria.Runner.Failure` when replay fails. The assertion converts controlled failures to
`ExUnit.AssertionError`; programmer misuse remains `ArgumentError`.

## Generated conformance workflow

Create a validated spec and let Victoria allocate a run, invoke Apalache, and verify every trace:

```elixir
{:ok, spec} =
  Victoria.Spec.new(
    source: "test/specs/Counter.tla",
    config: "test/specs/Counter.cfg"
  )

{:ok, result} =
  Victoria.Workflow.run(
    Counter.Model,
    spec,
    plan: [mode: :simulate, length: 10, max_run: 5]
  )
```

The ExUnit form runs the same workflow:

```elixir
import Victoria.ExUnit

:ok =
  assert_conform(
    Counter.Model,
    spec,
    plan: [mode: :simulate, length: 10, max_run: 5]
  )
```

Generated traces are verified sequentially in lexical artifact-path order, without deduplication. Every
trace gets a fresh model lifecycle and verification stops on the first failure.

## Verification semantics

For the initial state and after every executed step, Victoria performs exactly:

```text
expected = Model.project(step)
observed = Model.snapshot(impl)
expected === observed
```

Victoria does not calculate business outcomes in Elixir. The TLA+ trace supplies expected behavior and the
model exposes the corresponding implementation state. A mismatch returned directly from
`Victoria.Verifier.verify/2` is a public `Victoria.VerificationFailure`; replay wraps that semantic mismatch
with lifecycle context in `Victoria.Runner.Failure`.

## Artifacts and execution behavior

Generated workflows allocate an exclusive run directory below `tmp/victoria` by default. Its name contains
one UTC timestamp, the TLA+ source basename, and a random six-character hexadecimal suffix. The
`artifacts: [root: path]` workflow option selects another root.

The run directory is retained on success and failure. Victoria never empties, reuses, or automatically
removes it. `victoria-run.json` is written as `running` before Apalache starts and atomically replaced with a
`completed` manifest after materialization succeeds or fails. A process interruption can therefore leave a
retained `running` manifest; Victoria does not recover or resume it.

The manifest records absolute spec/config paths, the executable path, working and run directories, complete
argv, exit status, ordered relative trace paths, and a bounded output diagnostic. Do not place secrets in
paths or command options. The public `Victoria.Apalache.Result` retains complete raw subprocess output bytes.
Human-readable errors and manifests retain only a binary-safe tail of at most 4 KiB plus byte-count and
truncation metadata.

Only top-level regular `.itf.json` files are materialized; symlinks and nested files are ignored. A nonzero
Apalache exit can still be a successful materialization when one or more valid traces were produced. Trace
loading is all-or-nothing.

## Lower-level APIs

Advanced callers may explicitly compose:

```text
Victoria.Spec
  → Victoria.Apalache.RunDirectory
  → Victoria.Apalache.Plan
  → Victoria.Apalache.run/2
  → Victoria.Apalache.Result
  → Victoria.verify/2
```

Use these APIs when the caller must own the run path or separately inspect materialization before deciding
which traces to verify.

## Known limitations

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

## License

Victoria is available under the [MIT License](https://github.com/kokjinsam/victoria/blob/main/LICENSE).
