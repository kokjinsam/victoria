defmodule Victoria.ITFTest do
  use ExUnit.Case, async: true

  alias Victoria.ITF
  alias Victoria.ITF.Error
  alias Victoria.Step
  alias Victoria.Trace

  @fixtures Path.expand("fixtures", __DIR__)
  @traces Path.expand("traces", __DIR__)

  test "constructs a Trace from untouched Apalache 0.58.3 output" do
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
            }} = ITF.load(source)
  end

  test "normalizes parameterized state zero and excludes parameters from later states" do
    assert {:ok,
            %Trace{
              metadata: %{parameters: ["Limit"], itf: %{"source" => "synthetic"}},
              steps: [
                %Step{
                  action: "Initial",
                  state: %{
                    "Limit" => 123,
                    "value" => %{
                      "opaque" => "UNIT",
                      "uninterpreted" => "Node(1)",
                      "nested" => [true, %{"number" => -12}]
                    }
                  }
                },
                %Step{action: "Complete", state: %{"value" => "done"}}
              ]
            }} = load_fixture("formal_values.itf.json")
  end

  test "requires unique parameter names disjoint from variable names" do
    assert_error("duplicate_parameter.itf.json", :declaration_names_must_be_unique, ["params"])

    assert_error(
      "overlapping_parameter.itf.json",
      {:parameter_variable_overlap, "value"},
      ["params"]
    )
  end

  test "requires every parameter assignment in state zero" do
    assert_error(
      "missing_parameter_assignment.itf.json",
      :state_key_is_missing,
      ["states", 0, "Limit"]
    )
  end

  test "defaults a missing params declaration and does not require meta.format" do
    assert {:ok, %Trace{metadata: %{parameters: [], itf: %{}}}} = load_fixture("loop.itf.json")
  end

  test "rejects raw JSON numbers and null formal values" do
    assert_error("counter_numeric_type_mismatch.itf.json", :raw_json_number, ["states", 0, "count"])
    assert_error("null_value.itf.json", :null_formal_value, ["states", 0, "value"])
  end

  test "rejects malformed bigint values" do
    assert_error("malformed_bigint.itf.json", :malformed_bigint, ["states", 0, "value"])
    assert_error("newline_bigint.itf.json", :malformed_bigint, ["states", 0, "value"])
  end

  test "rejects unsupported and unknown reserved tags explicitly" do
    for {fixture_name, tag} <- [
          {"unsupported_set.itf.json", "#set"},
          {"unsupported_tuple.itf.json", "#tup"},
          {"unsupported_map.itf.json", "#map"},
          {"unsupported_unserializable.itf.json", "#unserializable"}
        ] do
      assert_error(fixture_name, {:unsupported_tag, tag}, ["states", 0, "value"])
    end

    assert_error(
      "unknown_tag.itf.json",
      {:unknown_reserved_tag, "#future"},
      ["states", 0, "value"]
    )
  end

  test "retains a nested value path and renders it usefully" do
    source = fixture("nested_raw_number.itf.json")

    assert {:error,
            %Error{
              source: ^source,
              reason: :raw_json_number,
              path: ["states", 0, "value", "items", 1, "count"]
            } = error} = ITF.load(source)

    assert Exception.message(error) =~ "states[0].value.items[1].count"
  end

  test "requires structural integer indices to match array positions" do
    assert_error(
      "invalid_index.itf.json",
      {:unexpected_state_index, 1},
      ["states", 0, "#meta", "index"]
    )
  end

  test "preserves a valid loop and rejects invalid or null loops" do
    assert {:ok, %Trace{loop_index: 1}} = load_fixture("loop.itf.json")

    assert_error("invalid_loop.itf.json", {:loop_index_out_of_range, 1}, ["loop"])
    assert_error("null_loop.itf.json", :loop_index_must_not_be_null, ["loop"])
    assert_error("fractional_loop.itf.json", :loop_index_must_be_an_integer, ["loop"])
  end

  test "requires state zero to use Initial" do
    assert_error(
      "non_initial.itf.json",
      :initial_action_must_be_initial,
      ["states", 0, "lastTransition"]
    )
  end

  test "rejects only consecutive equal action and normalized state" do
    assert_error("counter_stutter.itf.json", :unsupported_stutter, ["states", 2])

    assert {:ok,
            %Trace{
              steps: [
                %Step{action: "Initial", state: %{"count" => 0}},
                %Step{action: "Increment", state: %{"count" => 1}},
                %Step{action: "Observe", state: %{"count" => 1}}
              ]
            }} = load_fixture("counter_state_preserving_action.itf.json")
  end

  test "excludes initial parameters when detecting stutters" do
    assert {:error,
            %Error{
              reason: :unsupported_stutter,
              state_index: 1,
              action: "Initial",
              path: ["states", 1]
            }} = load_fixture("parameterized_initial_stutter.itf.json")
  end

  test "returns source-bearing read, decode, and state-shape errors" do
    missing = fixture("missing.itf.json")
    assert {:error, %Error{source: ^missing, kind: :read, reason: :enoent, path: []}} = ITF.load(missing)

    malformed_json = fixture("malformed_json.itf.json")
    assert {:error, %Error{source: ^malformed_json, kind: :decode}} = ITF.load(malformed_json)

    malformed_state = fixture("malformed_state.itf.json")

    assert {:error,
            %Error{
              source: ^malformed_state,
              kind: :shape,
              reason: :last_transition_must_be_a_string,
              path: ["states", 1, "lastTransition"]
            }} = ITF.load(malformed_state)
  end

  defp fixture(name), do: Path.join(@fixtures, name)
  defp load_fixture(name), do: name |> fixture() |> ITF.load()

  defp assert_error(name, reason, path) do
    assert {:error, %Error{kind: :shape, reason: ^reason, path: ^path}} = load_fixture(name)
  end
end
