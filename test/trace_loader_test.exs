defmodule Victoria.Trace.AdapterTest do
  use ExUnit.Case, async: true

  alias Victoria.Step
  alias Victoria.Trace
  alias Victoria.Trace.Error

  @fixtures Path.expand("fixtures", __DIR__)
  @traces Path.expand("traces", __DIR__)

  test "adapts untouched Apalache 0.58.3 output" do
    source = Path.join(@traces, "counter.itf.json")

    assert {:ok,
            %Trace{
              source: ^source,
              metadata: %{
                variables: ["count", "lastTransition"],
                parameters: [],
                source_format: :itf,
                itf: %{
                  "format" => "ITF",
                  "format-description" => _description,
                  "description" => _generated_at,
                  "varTypes" => %{"count" => "Int", "lastTransition" => "Str"}
                }
              },
              loop_index: nil,
              steps: [
                %Step{index: 0, action: "Initial", state: %{"count" => 0}},
                %Step{index: 1, action: "Increment", state: %{"count" => 1}},
                %Step{index: 2, action: "Increment", state: %{"count" => 2}},
                %Step{index: 3, action: "Decrement", state: %{"count" => 1}}
              ]
            }} = Trace.load(source)
  end

  test "keeps parameters only in the initial step and removes lastTransition" do
    assert {:ok,
            %Trace{
              metadata: %{parameters: ["Limit"], itf: %{"source" => "synthetic"}},
              steps: [
                %Step{action: "Initial", state: %{"Limit" => 123, "value" => initial_value}},
                %Step{action: "Complete", state: %{"value" => "done"}}
              ]
            }} = load_fixture("formal_values.itf.json")

    assert initial_value == %{
             "opaque" => "UNIT",
             "uninterpreted" => "Node(1)",
             "nested" => [true, %{"number" => -12}]
           }
  end

  test "requires declared, string-valued actions and Initial at state zero" do
    assert_error(
      "missing_last_transition.itf.json",
      :missing_last_transition_variable,
      ["vars"]
    )

    assert_error(
      "malformed_state.itf.json",
      :last_transition_must_be_a_string,
      ["states", 1, "lastTransition"]
    )

    assert_error(
      "non_initial.itf.json",
      :initial_action_must_be_initial,
      ["states", 0, "lastTransition"]
    )
  end

  test "uses exact action and declared variable values for stutter identity" do
    assert {:error,
            %Error{
              reason: :unsupported_stutter,
              state_index: 1,
              action: "Initial",
              path: ["states", 1]
            }} = load_fixture("parameterized_initial_stutter.itf.json")

    assert {:ok,
            %Trace{
              steps: [
                %Step{action: "Initial", state: %{"count" => 0}},
                %Step{action: "Increment", state: %{"count" => 1}},
                %Step{action: "Observe", state: %{"count" => 1}}
              ]
            }} = load_fixture("counter_state_preserving_action.itf.json")
  end

  test "copies loop index for Runner validation" do
    assert {:ok, %Trace{loop_index: 1}} = load_fixture("loop.itf.json")
  end

  test "derives step indices from state positions and ignores state metadata" do
    assert {:ok,
            %Trace{
              steps: [
                %Step{index: 0, action: "Initial", state: %{"count" => 0}},
                %Step{index: 1, action: "Increment", state: %{"count" => 1}},
                %Step{index: 2, action: "Double", state: %{"count" => 2}},
                %Step{index: 3, action: "Increment", state: %{"count" => 3}}
              ]
            }} = load_fixture("invalid_index.itf.json")
  end

  test "rejects state extensions" do
    assert_error(
      "undeclared_state_extension.itf.json",
      :state_keys_must_match_declarations,
      ["states", 0]
    )
  end

  test "passes standalone rich ITF values through unchanged" do
    assert {:ok,
            %Trace{
              steps: [
                %Step{state: %{"value" => %Elixir.ITF.Tuple{values: ["x"]}}}
              ]
            }} = load_fixture("unsupported_tuple.itf.json")
  end

  test "returns upstream ITF errors unchanged and Victoria adapter errors separately" do
    missing = fixture("missing.itf.json")
    assert {:error, %ITF.Error{} = missing_error} = Trace.load(missing)
    assert {:error, ^missing_error} = ITF.load(missing)

    malformed_json = fixture("malformed_json.itf.json")

    assert {:error, %ITF.Error{} = json_error} = Trace.load(malformed_json)
    assert {:error, ^json_error} = ITF.load(malformed_json)

    malformed_state = fixture("malformed_state.itf.json")

    assert {:error,
            %Error{
              source: ^malformed_state,
              reason: :last_transition_must_be_a_string,
              path: ["states", 1, "lastTransition"]
            }} = Trace.load(malformed_state)
  end

  defp fixture(name), do: Path.join(@fixtures, name)
  defp load_fixture(name), do: name |> fixture() |> Trace.load()

  defp assert_error(name, reason, path) do
    assert {:error, %Error{reason: ^reason, path: ^path}} = load_fixture(name)
  end
end
