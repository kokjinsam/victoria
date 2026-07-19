defmodule Victoria.ITF do
  @moduledoc "Loads the supported subset of the Informal Trace Format."

  alias Victoria.Step
  alias Victoria.Trace

  defmodule Error do
    @moduledoc "A structured ITF read, decode, or validation error."

    @enforce_keys [:source, :kind, :reason, :path]
    defexception [:source, :kind, :reason, :path, :state_index, :action]

    @type t :: %__MODULE__{
            source: Path.t(),
            kind: :read | :decode | :shape,
            reason: term(),
            path: [String.t() | non_neg_integer()],
            state_index: non_neg_integer() | nil,
            action: String.t() | nil
          }

    @impl Exception
    def message(error) do
      location = if error.path == [], do: error.source, else: "#{error.source}:#{format_path(error.path)}"
      "#{error.kind} error at #{location}: #{inspect(error.reason)}"
    end

    defp format_path([head | tail]) do
      Enum.reduce(tail, head, fn
        index, path when is_integer(index) -> "#{path}[#{index}]"
        key, path -> "#{path}.#{key}"
      end)
    end
  end

  @unsupported_tags ~w(#set #tup #map #unserializable)

  @spec load(Path.t()) :: {:ok, Trace.t()} | {:error, Error.t()}
  def load(path) do
    with {:ok, contents} <- read(path),
         {:ok, decoded} <- decode(contents, path),
         {:ok, document} <- validate_document(decoded, path),
         {:ok, steps} <- parse_states(document.states, document.variables, document.parameters, path),
         :ok <- validate_initial(steps, path),
         :ok <- reject_stutters(steps, document.variables, path) do
      {:ok,
       %Trace{
         source: path,
         metadata: %{
           variables: document.variables,
           parameters: document.parameters,
           source_format: :itf,
           itf: document.meta
         },
         steps: steps,
         loop_index: document.loop_index
       }}
    end
  end

  defp read(path) do
    case File.read(path) do
      {:ok, contents} -> {:ok, contents}
      {:error, reason} -> error(path, :read, reason)
    end
  end

  defp decode(contents, path) do
    case JSON.decode(contents) do
      {:ok, decoded} -> {:ok, decoded}
      {:error, reason} -> error(path, :decode, reason)
    end
  end

  defp validate_document(decoded, path) when is_map(decoded) do
    with {:ok, meta} <- require_map(decoded, "#meta", path),
         {:ok, variables} <- validate_declaration(decoded, "vars", false, path),
         :ok <- require_last_transition(variables, path),
         {:ok, parameters} <- validate_parameters(decoded, path),
         :ok <- reject_parameter_variable_overlap(parameters, variables, path),
         {:ok, states} <- validate_states(decoded, path),
         {:ok, loop_index} <- validate_loop(decoded, length(states), path) do
      {:ok,
       %{
         meta: meta,
         variables: variables,
         parameters: parameters,
         states: states,
         loop_index: loop_index
       }}
    end
  end

  defp validate_document(_decoded, path), do: error(path, :shape, :document_must_be_an_object)

  defp require_map(document, key, path) do
    case Map.fetch(document, key) do
      {:ok, value} when is_map(value) -> {:ok, value}
      :error -> error(path, :shape, :required_object_is_missing, [key])
      {:ok, _value} -> error(path, :shape, :must_be_an_object, [key])
    end
  end

  defp validate_declaration(document, key, allow_empty?, path) do
    case Map.fetch(document, key) do
      {:ok, values} when is_list(values) -> validate_declaration_values(values, key, allow_empty?, path)
      :error -> error(path, :shape, :required_declaration_is_missing, [key])
      {:ok, _value} -> error(path, :shape, :declaration_must_be_a_list, [key])
    end
  end

  defp validate_declaration_values([], key, false, path) do
    error(path, :shape, :declaration_must_be_nonempty, [key])
  end

  defp validate_declaration_values(values, key, _allow_empty?, path) do
    cond do
      not Enum.all?(values, &is_binary/1) ->
        error(path, :shape, :declaration_names_must_be_strings, [key])

      Enum.uniq(values) != values ->
        error(path, :shape, :declaration_names_must_be_unique, [key])

      true ->
        {:ok, values}
    end
  end

  defp validate_parameters(document, path) do
    case Map.fetch(document, "params") do
      :error ->
        {:ok, []}

      {:ok, _parameters} ->
        validate_declaration(document, "params", true, path)
    end
  end

  defp reject_parameter_variable_overlap(parameters, variables, path) do
    case Enum.find(parameters, &(&1 in variables)) do
      nil -> :ok
      name -> error(path, :shape, {:parameter_variable_overlap, name}, ["params"])
    end
  end

  defp require_last_transition(variables, path) do
    if "lastTransition" in variables do
      :ok
    else
      error(path, :shape, :missing_last_transition_variable, ["vars"])
    end
  end

  defp validate_states(document, path) do
    case Map.fetch(document, "states") do
      {:ok, []} -> error(path, :shape, :states_must_be_nonempty, ["states"])
      {:ok, states} when is_list(states) -> {:ok, states}
      :error -> error(path, :shape, :states_are_missing, ["states"])
      {:ok, _value} -> error(path, :shape, :states_must_be_a_list, ["states"])
    end
  end

  defp validate_loop(document, state_count, path) do
    case Map.fetch(document, "loop") do
      :error ->
        {:ok, nil}

      {:ok, loop_index} when is_integer(loop_index) and loop_index >= 0 and loop_index < state_count ->
        {:ok, loop_index}

      {:ok, loop_index} when is_integer(loop_index) ->
        error(path, :shape, {:loop_index_out_of_range, loop_index}, ["loop"])

      {:ok, nil} ->
        error(path, :shape, :loop_index_must_not_be_null, ["loop"])

      {:ok, _value} ->
        error(path, :shape, :loop_index_must_be_an_integer, ["loop"])
    end
  end

  defp parse_states(states, variables, parameters, path) do
    states
    |> Enum.with_index()
    |> Enum.reduce_while({:ok, []}, fn {state, index}, {:ok, steps} ->
      case parse_state(state, index, variables, parameters, path) do
        {:ok, step} -> {:cont, {:ok, [step | steps]}}
        {:error, error} -> {:halt, {:error, error}}
      end
    end)
    |> case do
      {:ok, steps} -> {:ok, Enum.reverse(steps)}
      error -> error
    end
  end

  defp parse_state(raw_state, index, variables, parameters, path) when is_map(raw_state) do
    state_path = ["states", index]
    declared_names = if index == 0, do: parameters ++ variables, else: variables

    with :ok <- validate_state_meta(raw_state, index, path, state_path),
         :ok <- validate_state_keys(raw_state, declared_names, path, state_path),
         {:ok, action} <- parse_action(raw_state, path, state_path, index),
         {:ok, state} <- normalize_state(raw_state, declared_names, path, state_path, index, action) do
      {:ok, %Step{index: index, action: action, state: state}}
    end
  end

  defp parse_state(_raw_state, index, _variables, _parameters, path) do
    error(path, :shape, :state_must_be_an_object, ["states", index], index)
  end

  defp validate_state_meta(raw_state, index, path, state_path) do
    case Map.fetch(raw_state, "#meta") do
      {:ok, %{"index" => ^index}} ->
        :ok

      {:ok, %{"index" => actual_index}} when is_integer(actual_index) ->
        error(path, :shape, {:unexpected_state_index, actual_index}, extend_path(state_path, ["#meta", "index"]), index)

      {:ok, %{"index" => _actual_index}} ->
        error(path, :shape, :state_index_must_be_an_integer, extend_path(state_path, ["#meta", "index"]), index)

      {:ok, meta} when is_map(meta) ->
        error(path, :shape, :state_index_is_missing, extend_path(state_path, ["#meta", "index"]), index)

      _other ->
        error(path, :shape, :state_meta_must_be_an_object, extend_path(state_path, ["#meta"]), index)
    end
  end

  defp validate_state_keys(raw_state, declared_names, path, state_path) do
    expected = ["#meta" | declared_names]
    actual = Map.keys(raw_state)

    case expected -- actual do
      [missing | _rest] ->
        error(path, :shape, :state_key_is_missing, extend_path(state_path, [missing]))

      [] ->
        if actual -- expected == [] do
          :ok
        else
          error(path, :shape, :state_keys_must_match_declarations, state_path)
        end
    end
  end

  defp parse_action(%{"lastTransition" => action}, _path, _state_path, _index) when is_binary(action), do: {:ok, action}

  defp parse_action(_raw_state, path, state_path, index) do
    error(path, :shape, :last_transition_must_be_a_string, extend_path(state_path, ["lastTransition"]), index)
  end

  defp normalize_state(raw_state, variables, path, state_path, index, action) do
    variables
    |> Enum.reject(&(&1 == "lastTransition"))
    |> Enum.reduce_while({:ok, %{}}, fn variable, {:ok, normalized} ->
      value_path = extend_path(state_path, [variable])

      case normalize_value(Map.fetch!(raw_state, variable), path, value_path, index, action) do
        {:ok, value} -> {:cont, {:ok, Map.put(normalized, variable, value)}}
        {:error, error} -> {:halt, {:error, error}}
      end
    end)
  end

  defp normalize_value(value, _source, _path, _index, _action) when is_boolean(value) or is_binary(value),
    do: {:ok, value}

  defp normalize_value(values, source, path, index, action) when is_list(values) do
    values
    |> Enum.with_index()
    |> Enum.reduce_while({:ok, []}, fn {value, value_index}, {:ok, normalized} ->
      case normalize_value(value, source, extend_path(path, [value_index]), index, action) do
        {:ok, normalized_value} -> {:cont, {:ok, [normalized_value | normalized]}}
        {:error, error} -> {:halt, {:error, error}}
      end
    end)
    |> case do
      {:ok, normalized} -> {:ok, Enum.reverse(normalized)}
      error -> error
    end
  end

  defp normalize_value(%{"#bigint" => decimal} = value, source, path, index, action) when map_size(value) == 1 do
    if is_binary(decimal) and Regex.match?(~r/^-?[0-9]+\z/, decimal) do
      {:ok, String.to_integer(decimal)}
    else
      error(source, :shape, :malformed_bigint, path, index, action)
    end
  end

  defp normalize_value(value, source, path, index, action) when is_map(value) do
    value
    |> Map.keys()
    |> Enum.find(&String.starts_with?(&1, "#"))
    |> case do
      "#bigint" ->
        error(source, :shape, :malformed_bigint, path, index, action)

      tag when tag in @unsupported_tags ->
        error(source, :shape, {:unsupported_tag, tag}, path, index, action)

      tag when is_binary(tag) ->
        error(source, :shape, {:unknown_reserved_tag, tag}, path, index, action)

      nil ->
        normalize_record(value, source, path, index, action)
    end
  end

  defp normalize_value(nil, source, path, index, action) do
    error(source, :shape, :null_formal_value, path, index, action)
  end

  defp normalize_value(value, source, path, index, action) when is_number(value) do
    error(source, :shape, :raw_json_number, path, index, action)
  end

  defp normalize_value(_value, source, path, index, action) do
    error(source, :shape, :unsupported_formal_value, path, index, action)
  end

  defp normalize_record(record, source, path, index, action) do
    Enum.reduce_while(record, {:ok, %{}}, fn {key, value}, {:ok, normalized} ->
      case normalize_value(value, source, extend_path(path, [key]), index, action) do
        {:ok, normalized_value} -> {:cont, {:ok, Map.put(normalized, key, normalized_value)}}
        {:error, error} -> {:halt, {:error, error}}
      end
    end)
  end

  defp validate_initial([%Step{action: "Initial"} | _steps], _path), do: :ok

  defp validate_initial([%Step{action: action} | _steps], path) do
    error(path, :shape, :initial_action_must_be_initial, ["states", 0, "lastTransition"], 0, action)
  end

  defp reject_stutters(steps, variables, path) do
    comparison_variables = Enum.reject(variables, &(&1 == "lastTransition"))

    steps
    |> Enum.chunk_every(2, 1, :discard)
    |> Enum.find(fn [previous, current] ->
      previous.action === current.action and
        Map.take(previous.state, comparison_variables) === Map.take(current.state, comparison_variables)
    end)
    |> case do
      nil ->
        :ok

      [_previous, current] ->
        error(path, :shape, :unsupported_stutter, ["states", current.index], current.index, current.action)
    end
  end

  defp extend_path(path, suffix), do: Enum.concat(path, suffix)

  defp error(source, kind, reason, path \\ [], state_index \\ nil, action \\ nil) do
    {:error,
     %Error{
       source: source,
       kind: kind,
       reason: reason,
       path: path,
       state_index: state_index,
       action: action
     }}
  end
end
