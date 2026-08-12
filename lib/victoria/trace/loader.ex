defmodule Victoria.Trace.Loader do
  @moduledoc false

  alias Victoria.Step
  alias Victoria.Trace
  alias Victoria.Trace.Error

  @spec load(Path.t()) :: {:ok, Trace.t()} | {:error, ITF.Error.t() | Error.t()}
  def load(path) do
    with {:ok, trace} <- ITF.load(path) do
      adapt(trace, path)
    end
  end

  defp adapt(%ITF.Trace{} = trace, path) do
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
    if "lastTransition" in variables,
      do: :ok,
      else: error(path, :missing_last_transition_variable, ["vars"])
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

  defp adapt_state(%ITF.State{} = state, index, variables, parameters, path) do
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
    error(path, :state_keys_must_match_declarations, state_path, index)
  end

  defp parse_action(%{"lastTransition" => action}, _path, _state_path, _index) when is_binary(action), do: {:ok, action}

  defp parse_action(_values, path, state_path, index) do
    error(path, :last_transition_must_be_a_string, Enum.concat(state_path, ["lastTransition"]), index)
  end

  defp validate_initial([%Step{action: "Initial"} | _steps], _path), do: :ok

  defp validate_initial([%Step{action: action} | _steps], path) do
    error(path, :initial_action_must_be_initial, ["states", 0, "lastTransition"], 0, action)
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
      nil -> :ok
      [_previous, current] -> error(path, :unsupported_stutter, ["states", current.index], current.index, current.action)
    end
  end

  defp error(source, reason, path, state_index \\ nil, action \\ nil) do
    {:error, %Error{source: source, reason: reason, path: path, state_index: state_index, action: action}}
  end
end
