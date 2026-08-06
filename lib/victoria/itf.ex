defmodule Victoria.ITF do
  @moduledoc """
  Adapts decoded Informal Trace Format documents for Victoria replay.

  The standalone `ITF` package owns file reading and format decoding.
  `Victoria.Trace.load/1` is the preferred public entry point.
  """

  alias Victoria.Step
  alias Victoria.Trace

  defmodule Error do
    @moduledoc """
    A structured ITF read, decode, or adaptation error.

    Errors are returned by the loader and should be treated as read-only.
    """

    @enforce_keys [:source, :kind, :reason, :path]
    defexception [:source, :kind, :reason, :path, :state_index, :action]

    @typedoc "An ITF error with source and nested value-path context."
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

  @spec load(Path.t()) :: {:ok, Trace.t()} | {:error, Error.t()}
  @doc "Loads `path` through `ITF.load/1` and adapts it for Victoria replay."
  def load(path) do
    case Elixir.ITF.load(path) do
      {:ok, trace} -> adapt(trace, path)
      {:error, error} -> {:error, translate_error(error)}
    end
  end

  defp adapt(%Elixir.ITF.Trace{} = trace, path) do
    with :ok <- require_last_transition(trace.vars, path),
         {:ok, steps} <- adapt_states(trace.states, trace.vars, trace.params, path),
         :ok <- validate_initial(steps, path),
         :ok <- reject_stutters(steps, trace.vars, path) do
      {:ok,
       %Trace{
         source: path,
         metadata: %{
           variables: trace.vars,
           parameters: trace.params,
           source_format: :itf,
           itf: trace.metadata
         },
         steps: steps,
         loop_index: trace.loop_index
       }}
    end
  end

  defp require_last_transition(variables, path) do
    if "lastTransition" in variables do
      :ok
    else
      error(path, :shape, :missing_last_transition_variable, ["vars"])
    end
  end

  defp adapt_states(states, variables, parameters, path) do
    states
    |> Enum.with_index()
    |> Enum.reduce_while({:ok, []}, fn {state, index}, {:ok, steps} ->
      case adapt_state(state, index, variables, parameters, path) do
        {:ok, step} -> {:cont, {:ok, [step | steps]}}
        {:error, _error} = failure -> {:halt, failure}
      end
    end)
    |> case do
      {:ok, steps} -> {:ok, Enum.reverse(steps)}
      failure -> failure
    end
  end

  defp adapt_state(%Elixir.ITF.State{} = state, index, variables, parameters, path) do
    state_path = ["states", index]
    replay_names = if index == 0, do: parameters ++ variables, else: variables

    with :ok <- reject_state_extensions(state.extensions, path, state_path, index),
         {:ok, action} <- parse_action(state.values, path, state_path, index) do
      replay_state = state.values |> Map.take(replay_names) |> Map.delete("lastTransition")
      {:ok, %Step{index: index, action: action, state: replay_state}}
    end
  end

  defp reject_state_extensions(extensions, _path, _state_path, _index) when map_size(extensions) == 0, do: :ok

  defp reject_state_extensions(_extensions, path, state_path, index) do
    error(path, :shape, :state_keys_must_match_declarations, state_path, index)
  end

  defp parse_action(%{"lastTransition" => action}, _path, _state_path, _index) when is_binary(action), do: {:ok, action}

  defp parse_action(_values, path, state_path, index) do
    error(path, :shape, :last_transition_must_be_a_string, extend_path(state_path, ["lastTransition"]), index)
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

  defp translate_error(%Elixir.ITF.Error{source: source, path: path, reason: {:file_error, reason}}) do
    %Error{source: source, kind: :read, reason: reason, path: path}
  end

  defp translate_error(%Elixir.ITF.Error{source: source, path: path, reason: :not_regular_file}) do
    %Error{source: source, kind: :read, reason: :not_regular_file, path: path}
  end

  defp translate_error(%Elixir.ITF.Error{source: source, path: path, reason: {:input_too_large, _limit} = reason}) do
    %Error{source: source, kind: :read, reason: reason, path: path}
  end

  defp translate_error(%Elixir.ITF.Error{source: source, path: path, reason: :invalid_json}) do
    %Error{source: source, kind: :decode, reason: :invalid_json, path: path}
  end

  defp translate_error(%Elixir.ITF.Error{source: source, path: path, reason: reason}) do
    %Error{source: source, kind: :shape, reason: reason, path: path}
  end

  defp extend_path(path, suffix), do: Enum.concat(path, suffix)

  defp error(source, kind, reason, path, state_index \\ nil, action \\ nil) do
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
