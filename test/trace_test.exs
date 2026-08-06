defmodule Victoria.TraceTest do
  use ExUnit.Case, async: true

  alias Victoria.ITF.Error
  alias Victoria.Trace

  @fixtures Path.expand("fixtures", __DIR__)
  @traces Path.expand("traces", __DIR__)

  test "loads a validated trace through the public API" do
    source = Path.join(@traces, "counter.itf.json")

    assert {:ok, %Trace{source: ^source}} = Trace.load(source)
  end

  test "preserves Victoria read, decode, and adaptation errors" do
    missing = fixture("missing.itf.json")
    assert {:error, %Error{source: ^missing, kind: :read, reason: :enoent, path: []}} = Trace.load(missing)

    malformed_json = fixture("malformed_json.itf.json")

    assert {:error, %Error{source: ^malformed_json, kind: :decode, reason: :invalid_json}} =
             Trace.load(malformed_json)

    malformed_state = fixture("malformed_state.itf.json")

    assert {:error,
            %Error{
              source: ^malformed_state,
              kind: :shape,
              reason: :last_transition_must_be_a_string,
              path: ["states", 1, "lastTransition"]
            }} = Trace.load(malformed_state)
  end

  defp fixture(name), do: Path.join(@fixtures, name)
end
