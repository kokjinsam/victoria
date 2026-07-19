# Victoria

Model-based testing with the Apalache TLA+ model checker.

Victoria replays one fixed ITF trace against one model, sequentially, and stops at the first failure.

## Fixed-trace replay

Load and validate the ITF document first, then replay the resulting `Victoria.Trace`:

```elixir
case Victoria.ITF.load("test/traces/counter.itf.json") do
  {:ok, trace} ->
    case Victoria.Runner.replay(trace, MyCounterModel) do
      {:ok, report} -> IO.inspect(report)
      {:error, failure} -> IO.puts(Exception.message(failure))
    end

  {:error, error} ->
    IO.puts(Exception.message(error))
end
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

The current boundary does not include `Victoria.assert_conform/2`, `Victoria.Spec`, `Model.spec/0`,
Victoria-owned Apalache invocation or trace generation, lasso execution, rich tagged values beyond
`#bigint`, shrinking, random testing, or executable reference models.

## Prior Art

1. [property_damage](https://github.com/property-damage/property_damage)
2. [tla_connect](https://github.com/sig-id/tla-connect-elixir)
3. [quint-connect](https://docs.rs/quint-connect/latest/quint_connect/)

## License

MIT License. See [LICENSE](./LICENSE) for details.
