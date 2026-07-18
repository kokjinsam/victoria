defmodule Victoria.ITF do
  @moduledoc false

  alias Victoria.Step

  defmodule Error do
    @moduledoc false
    @enforce_keys [:kind, :reason]
    defstruct [:kind, :reason, :state_index, :action]

    @type t :: %__MODULE__{
            kind: :read | :decode | :shape,
            reason: term(),
            state_index: non_neg_integer() | nil,
            action: String.t() | nil
          }
  end

  @spec load(Path.t()) :: {:ok, [Step.t(), ...]} | {:error, Error.t()}
  def load(path) do
    with {:ok, contents} <- read(path),
         {:ok, decoded} <- decode(contents),
         {:ok, variables, states} <- validate_document(decoded),
         {:ok, steps} <- parse_states(states, variables),
         :ok <- reject_stutters(steps) do
      {:ok, steps}
    end
  end

  defp read(path) do
    case File.read(path) do
      {:ok, contents} -> {:ok, contents}
      {:error, reason} -> error(:read, reason)
    end
  end

  defp decode(contents) do
    case JSON.decode(contents) do
      {:ok, decoded} -> {:ok, decoded}
      {:error, reason} -> error(:decode, reason)
    end
  end

  defp validate_document(%{"#meta" => %{"format" => "ITF"}, "vars" => variables, "states" => states})
       when is_list(variables) and is_list(states) do
    cond do
      variables == [] -> error(:shape, :variables_must_be_a_non_empty_list)
      states == [] -> error(:shape, :states_must_be_a_non_empty_list)
      not Enum.all?(variables, &is_binary/1) -> error(:shape, :variables_must_be_strings)
      Enum.uniq(variables) != variables -> error(:shape, :variables_must_be_unique)
      "lastTransition" not in variables -> error(:shape, :missing_last_transition_variable)
      true -> {:ok, variables, states}
    end
  end

  defp validate_document(_decoded) do
    error(:shape, :expected_itf_object_with_meta_variables_and_states)
  end

  defp parse_states(states, variables) do
    states
    |> Enum.with_index()
    |> Enum.reduce_while({:ok, []}, fn {state, index}, {:ok, steps} ->
      case parse_state(state, index, variables) do
        {:ok, step} -> {:cont, {:ok, [step | steps]}}
        {:error, failure} -> {:halt, {:error, failure}}
      end
    end)
    |> case do
      {:ok, steps} -> validate_initial(Enum.reverse(steps))
      error -> error
    end
  end

  defp parse_state(%{"#meta" => %{"index" => index}} = raw_state, index, variables) do
    expected_keys = MapSet.new(["#meta" | variables])
    actual_keys = raw_state |> Map.keys() |> MapSet.new()

    with :ok <- validate_keys(actual_keys, expected_keys, index),
         {:ok, action} <- parse_action(raw_state, index),
         {:ok, state} <- parse_formal_state(raw_state, variables, index, action) do
      {:ok, %Step{index: index, action: action, state: state}}
    end
  end

  defp parse_state(%{"#meta" => %{"index" => actual_index}}, index, _variables) do
    error(:shape, {:unexpected_state_index, actual_index}, index)
  end

  defp parse_state(state, index, _variables) when is_map(state) do
    error(:shape, :state_meta_must_contain_its_index, index)
  end

  defp parse_state(_state, index, _variables) do
    error(:shape, :state_must_be_an_object, index)
  end

  defp validate_keys(actual, expected, index) do
    if MapSet.equal?(actual, expected) do
      :ok
    else
      error(:shape, :state_keys_must_match_variables, index)
    end
  end

  defp parse_action(%{"lastTransition" => action}, _index) when is_binary(action), do: {:ok, action}

  defp parse_action(_state, index) do
    error(:shape, :last_transition_must_be_a_string, index)
  end

  defp parse_formal_state(raw_state, variables, index, action) do
    state = raw_state |> Map.take(variables) |> Map.delete("lastTransition")

    case unsupported_value(state) do
      nil -> {:ok, state}
      reason -> error(:shape, reason, index, action)
    end
  end

  defp unsupported_value(value) when is_map(value) do
    Enum.find_value(value, fn
      {"#" <> _rest = tag, _nested} -> {:unsupported_typed_value, tag}
      {_key, nested} -> unsupported_value(nested)
    end)
  end

  defp unsupported_value(values) when is_list(values) do
    Enum.find_value(values, &unsupported_value/1)
  end

  defp unsupported_value(_value), do: nil

  defp validate_initial([%Step{action: "Initial"} | _steps] = steps), do: {:ok, steps}

  defp validate_initial([%Step{action: action} | _steps]) do
    error(:shape, :initial_action_must_be_initial, 0, action)
  end

  defp reject_stutters(steps) do
    steps
    |> Enum.chunk_every(2, 1, :discard)
    |> Enum.find(fn [previous, current] ->
      previous.action === current.action and previous.state === current.state
    end)
    |> case do
      nil ->
        :ok

      [_previous, current] ->
        error(:shape, :unsupported_stutter, current.index, current.action)
    end
  end

  defp error(kind, reason, state_index \\ nil, action \\ nil) do
    {:error, %Error{kind: kind, reason: reason, state_index: state_index, action: action}}
  end
end
