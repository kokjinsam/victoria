# Victoria

Model-based testing with the Apalache TLA+ model checker.

Victoria materializes formal traces with Apalache and verifies them against an implementation model.

## Conformance workflow

The high-level workflow allocates an Apalache run and verifies every materialized trace:

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
    plan: [
      mode: :simulate,
      length: 10,
      max_run: 5
    ]
  )
```

The run directory is allocated automatically from one UTC timestamp and a fresh random suffix. Victoria
retries only exact directory-name collisions, up to eight total attempts. The existing Apalache artifacts
and `victoria-run.json` manifest are retained on success or failure; the workflow does not write a second
workflow-level manifest.

Generated traces are verified sequentially in materialization order without deduplication. Every trace is
passed independently to `Victoria.verify/2`, so each receives a fresh implementation lifecycle. Verification
stops on the first failure, and the workflow error retains prior successful reports together with the complete
Apalache result. A successful `%Victoria.Workflow.Result{}` means every materialized trace conformed.

The workflow is synchronous and has no timeout. Callers that need direct control of the run directory or any
lower-level step can continue to use the explicit `Spec` → `RunDirectory` → `Plan` → `Apalache.run` →
`Victoria.verify` APIs below. ExUnit callers can use `Victoria.ExUnit.assert_conform/3` to run the complete
workflow while retaining `assert_conform/2` for one existing fixed trace.

## ExUnit conformance assertions

Import the plain assertion functions to verify either a fixed trace or generated traces:

```elixir
import Victoria.ExUnit

# Verify one existing fixed trace.
:ok =
  assert_conform(
    Counter.Model,
    trace: "test/traces/counter.itf.json"
  )

# Generate traces and verify all of them.
{:ok, spec} =
  Victoria.Spec.new(
    source: "test/specs/Counter.tla",
    config: "test/specs/Counter.cfg"
  )

:ok =
  assert_conform(
    Counter.Model,
    spec,
    plan: [
      mode: :simulate,
      length: 10,
      max_run: 5
    ]
  )
```

The generated form requires a validated `%Victoria.Spec{}` and the supported Apalache v0.58.3 executable.
It invokes Apalache synchronously, allocates a run directory automatically, and retains all Apalache
artifacts and `victoria-run.json`. Generated ITF traces are validated and then verified in deterministic
materialization order. Every trace, including duplicates, receives a fresh implementation lifecycle, and
verification stops after the first failure.

Both assertions return only `:ok` on success. Controlled Victoria failures become
`ExUnit.AssertionError` with their authoritative messages; invalid models, Specs, and options remain
`ArgumentError`. Call `Victoria.Workflow.run/3` directly when the workflow result, reports, trace paths, or
other artifact details are needed programmatically. Generated assertions may block indefinitely because
Victoria currently provides no workflow timeout; tag real-Apalache tests separately when appropriate.

## Apalache planning and execution

Victoria validates formal artifacts, constructs deterministic Apalache plans, and materializes every valid
ITF trace produced by a plan:

```elixir
{:ok, spec} =
  Victoria.Spec.new(
    source: "test/specs/Counter.tla",
    config: "test/specs/Counter.cfg"
  )

run_directory =
  Victoria.Apalache.RunDirectory.build(spec,
    generated_at: DateTime.utc_now(),
    suffix: "a1b2c3"
  )

plan =
  Victoria.Apalache.Plan.new(spec,
    mode: :simulate,
    length: 10,
    max_run: 5,
    run_directory: run_directory
  )

{:ok, result} = Victoria.Apalache.run(plan)

verification_results =
  Enum.map(result.traces, fn trace ->
    Victoria.verify(Counter.Model, trace: trace)
  end)
```

`Victoria.Apalache.run/2` supports exactly Apalache v0.58.3. It probes the installed executable locally and
never queries the network. Bare executable names resolve through `PATH`; explicit relative paths resolve
against the process working directory when `run/2` is called. The plan's arguments are passed directly to
the executable without a shell, and its working directory is honored.

Execution is synchronous and may block until Apalache and its SMT solver terminate. Victoria enforces no
timeout, inherits the caller's process environment, and retains the exclusively reserved run directory on
success and failure. The call preserves complete merged process output and the raw exit status. A successful
result may have a nonzero exit status when Apalache produced counterexample traces: success means that one or
more top-level ITF artifacts were discovered and every one passed `Victoria.Trace.load/1` validation.

Every successfully reserved run directory receives `victoria-run.json`. Victoria commits a `running`
manifest before starting Apalache and replaces it with a `completed` manifest after execution and trace
materialization. A completed outcome is `materialized` when one or more valid traces were loaded, including
when Apalache exited nonzero, and `failed` when execution or materialization failed. Manifest trace paths are
relative to the run directory; `%Victoria.Apalache.Result{}` continues to carry absolute trace paths and the
complete raw output bytes. The manifest stores only a valid UTF-8 diagnostic tail of at most 4 KiB together
with the complete output byte size and a truncation flag.

Manifest replacement writes a complete temporary document in the run directory and renames it over the
previous document, so observers do not see partially written JSON. This atomic-visibility guarantee does not
include file or directory `fsync` and therefore is not a power-loss durability guarantee. Victoria retains
completed, failed, and interrupted artifacts. It does not recover or resume a directory whose manifest
remains `running`, and it provides no timeout or cancellation. The manifest records no environment data.
Formal artifact paths and Apalache arguments are recorded as supplied by the validated plan, so callers
should not place secrets in paths or command-line options without a separate redaction design.

Result traces are plural, lexically ordered by their absolute artifact paths, and loaded all-or-nothing.
`Victoria.Apalache.run/2` only materializes traces; it does not replay them or verify an implementation.
Callers choose explicitly which returned traces to pass to `Victoria.verify/2`.

Run names combine a UTC timestamp, a slug derived from the `.tla` basename, and a caller-supplied
six-character lowercase hexadecimal suffix. Given the same inputs, naming and planning are deterministic.
Planning remains pure and version-free; `Victoria.Apalache.run/2` is the execution boundary that pins
v0.58.3.

## Fixed-trace replay

Load and validate an ITF document through the public trace API:

```elixir
case Victoria.Trace.load("test/traces/counter.itf.json") do
  {:ok, trace} ->
    case Victoria.verify(MyCounterModel, trace: trace) do
      {:ok, report} -> IO.inspect(report)
      {:error, failure} -> IO.puts(Exception.message(failure))
    end

  {:error, error} ->
    IO.puts(Exception.message(error))
end
```

`Victoria.verify/2` accepts either a path or an existing validated `Victoria.Trace`:

```elixir
{:ok, report} = Victoria.verify(MyCounterModel, trace: "test/traces/counter.itf.json")
{:ok, report} = Victoria.verify(MyCounterModel, trace: trace)
```

It returns `{:ok, %Victoria.Runner.Report{}}` when the trace conforms, an
`{:error, %Victoria.ITF.Error{}}` when loading fails, or an
`{:error, %Victoria.Runner.Failure{}}` when replay fails. Loading and verification errors retain their
existing `Exception.message/1` renderers.

The fixed-trace form of the plain ExUnit assertion returns `:ok` on success and converts either controlled
error into an `ExUnit.AssertionError` using the same rendering:

```elixir
import Victoria.ExUnit

:ok = assert_conform(MyCounterModel, trace: "test/traces/counter.itf.json")
```

Every raw state must contain a string `"lastTransition"` field. Victoria turns that field into
`Victoria.Step.action` and removes it from `Victoria.Step.state`. State zero must use `"Initial"`. It
initializes the implementation and is verified through `snapshot/1` and `project/1`, but it is never
executed. Every later step is executed once and then verified. The formal projection is the expected state;
the implementation snapshot is the observed state. Verification compares those maps with exact equality
(`===`). A trace conforms when every expected state equals its observed state. The implementation value is
opaque to Victoria and is only threaded through model callbacks.

Victoria accepts ITF booleans, strings, recursively nested JSON arrays and record objects, and tagged
integers of the form `{"#bigint": "<signed decimal>"}`. Strings are always preserved verbatim, including
`UNIT`-shaped or uninterpreted values; Victoria does not infer formal types from them. Raw JSON numbers,
JSON `null`, malformed big integers, `#set`, `#tup`, `#map`, `#unserializable`, and unknown reserved tags
are rejected with a source-bearing structured value path.

Consecutive steps are rejected as an unsupported stutter only when both their normalized state and action
are equal. An equal state with a different action remains an observable command occurrence.

Finite traces are supported. ITF lasso traces retain their `loop` index in `Victoria.Trace`, but Runner
returns a `:trace_validation` failure before model initialization because lasso execution is not yet
supported.

If `init/1` succeeds, optional `cleanup/1` runs once on every controlled exit. This boundary intentionally
has no timeout, crash isolation, guardian, or lifecycle state machine.

## Trace storage

Real, byte-for-byte model-checker output belongs in `test/traces`; its provenance is recorded in that
directory. Synthetic valid, malformed, and boundary documents belong in `test/fixtures`. TLA+ models and
their TLC-style Apalache configs belong in `test/specs`. Generated checker work stays under ignored
`tmp`.

## Deferred work

The current boundary does not include `Model.spec/0`, a `Victoria.generate/…` convenience, workflow
manifests, configurable workflow retries, continue-after-failure verification,
parallelism, deduplication, timeouts, cancellation, Docker support, environment overrides, artifact cleanup,
campaigns, lasso execution, rich tagged values beyond `#bigint`, shrinking, random testing, or executable
reference models.

## Prior Art

1. [property_damage](https://github.com/property-damage/property_damage)
2. [tla_connect](https://github.com/sig-id/tla-connect-elixir)
3. [quint-connect](https://docs.rs/quint-connect/latest/quint_connect/)

## License

MIT License. See [LICENSE](./LICENSE) for details.
