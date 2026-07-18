# Victoria

Model-based testing with Apalache TLA+ model checker.

Victoria's first replay boundary is deliberately small: it replays one fixed
ITF trace against one model, sequentially, and stops at the first failure.

## Fixed-trace replay

Call `Victoria.Runner.replay/2` with an ITF JSON file and a module implementing
`Victoria.Model`:

```elixir
case Victoria.Runner.replay("test/fixtures/counter.itf.json", MyCounterModel) do
  {:ok, report} -> IO.inspect(report)
  {:error, failure} -> IO.puts(Exception.message(failure))
end
```

Every raw state must contain a string `"lastTransition"` field. Victoria turns
that field into `Victoria.Step.action`; the remaining map is
`Victoria.Step.state`. State zero must use the action `"Initial"`. It initializes
the implementation and is checked through `snapshot/1` and `project/1`, but it
is never executed. Every later step is executed once, then the implementation
snapshot and formal projection are compared with exact equality (`===`). The
implementation value is opaque to Victoria and is only threaded through model
callbacks.

Consecutive identical formal states are unsupported stutters. Victoria rejects
them before executing their transition. Skipping stutters can only be safe once
real command occurrences can be distinguished reliably from state-preserving
behavior, for example with an occurrence marker.

If `init/1` succeeds, optional `cleanup/1` runs once on every controlled exit.
This MVP intentionally has no timeout, crash isolation, guardian, or lifecycle
state machine.

Trace generation, shrinking, random testing, fully typed ITF values,
`Victoria.assert_refines`, `use Victoria` integration, `Victoria.Spec`, and
model-provided specifications are outside this fixed-trace MVP.

## Prior Art

1. [property_damage](https://github.com/property-damage/property_damage)
2. [tla_connect](https://github.com/sig-id/tla-connect-elixir)
3. [quint-connect](https://docs.rs/quint-connect/latest/quint_connect/)

## License

MIT License. See [LICENSE](./LICENSE) for details.
