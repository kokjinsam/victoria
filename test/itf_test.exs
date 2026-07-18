defmodule Victoria.ITFTest do
  use ExUnit.Case, async: true

  alias Victoria.ITF
  alias Victoria.ITF.Error
  alias Victoria.Step

  @fixtures Path.expand("fixtures", __DIR__)

  test "normalizes the real-shaped Counter fixture into strict steps" do
    assert {:ok,
            [
              %Step{index: 0, action: "Initial", state: %{"count" => 0}},
              %Step{index: 1, action: "Increment", state: %{"count" => 1}},
              %Step{index: 2, action: "Increment", state: %{"count" => 2}},
              %Step{index: 3, action: "Decrement", state: %{"count" => 1}}
            ]} = load_fixture("counter.itf.json")
  end

  test "accepts a state-preserving command with a different action" do
    assert {:ok,
            [
              %Step{index: 0, action: "Initial", state: %{"count" => 0}},
              %Step{index: 1, action: "Increment", state: %{"count" => 1}},
              %Step{index: 2, action: "Observe", state: %{"count" => 1}}
            ]} = load_fixture("counter_state_preserving_action.itf.json")
  end

  test "rejects malformed JSON and malformed state actions clearly" do
    assert {:error, %Error{kind: :decode}} = load_fixture("malformed_json.itf.json")

    assert {:error,
            %Error{
              kind: :shape,
              reason: :last_transition_must_be_a_string,
              state_index: 1
            }} = load_fixture("malformed_state.itf.json")
  end

  test "rejects typed ITF values outside the fixed JSON-native subset" do
    assert {:error,
            %Error{
              kind: :shape,
              reason: {:unsupported_typed_value, "#bigint"},
              state_index: 0,
              action: "Initial"
            }} = load_fixture("counter_typed_value.itf.json")
  end

  defp fixture(name), do: Path.join(@fixtures, name)
  defp load_fixture(name), do: name |> fixture() |> ITF.load()
end
