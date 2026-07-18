defmodule Victoria.Runner do
  @moduledoc "Sequential fixed-trace replay."

  alias Victoria.ITF
  alias Victoria.Runner.Failure
  alias Victoria.Runner.Report

  @spec replay(Path.t(), module()) :: {:ok, Report.t()} | {:error, Failure.t()}
  def replay(trace_path, model) do
    case ITF.load(trace_path) do
      {:ok, [initial | steps]} -> initialize(trace_path, model, initial, steps)
      {:error, error} -> {:error, trace_failure(trace_path, model, error)}
    end
  end

  defp initialize(trace_path, model, initial, steps) do
    case callback(model, :init, [initial.state]) do
      {:ok, {:ok, implementation}} ->
        replay_result = replay_initialized(trace_path, model, initial, steps, implementation)
        finish(replay_result, cleanup(model, cleanup_implementation(replay_result)), trace_path, model)

      {:ok, {:error, reason}} ->
        {:error, failure(trace_path, model, :initialization, reason, initial)}

      {:ok, returned} ->
        {:error, failure(trace_path, model, :initialization, {:invalid_return, returned}, initial)}

      {:raised, exception} ->
        {:error, failure(trace_path, model, :initialization, {:raised, exception}, initial)}
    end
  end

  defp replay_initialized(trace_path, model, initial, steps, implementation) do
    case compare(trace_path, model, initial, implementation, :initial_refinement) do
      :ok -> run_steps(trace_path, model, steps, implementation, 0)
      {:error, replay_failure} -> {:error, replay_failure, implementation}
    end
  end

  defp run_steps(_trace_path, _model, [], implementation, executed_count) do
    {:ok, implementation, executed_count}
  end

  defp run_steps(trace_path, model, [step | rest], implementation, executed_count) do
    case callback(model, :execute, [step, implementation]) do
      {:ok, {:ok, next_implementation}} ->
        case compare(trace_path, model, step, next_implementation, :step_refinement) do
          :ok -> run_steps(trace_path, model, rest, next_implementation, executed_count + 1)
          {:error, replay_failure} -> {:error, replay_failure, next_implementation}
        end

      {:ok, {:error, reason}} ->
        {:error, failure(trace_path, model, :execution, reason, step), implementation}

      {:ok, returned} ->
        {:error, failure(trace_path, model, :execution, {:invalid_return, returned}, step), implementation}

      {:raised, exception} ->
        {:error, failure(trace_path, model, :execution, {:raised, exception}, step), implementation}
    end
  end

  defp compare(trace_path, model, step, implementation, mismatch_phase) do
    with {:ok, observed} <- map_callback(trace_path, model, :snapshot, implementation, step),
         {:ok, expected} <- map_callback(trace_path, model, :projection, step, step) do
      if observed === expected do
        :ok
      else
        {:error,
         failure(
           trace_path,
           model,
           mismatch_phase,
           :refinement_mismatch,
           step,
           expected,
           observed
         )}
      end
    end
  end

  defp map_callback(trace_path, model, :snapshot = name, argument, step) do
    validate_map_callback(trace_path, model, name, callback(model, name, [argument]), step)
  end

  defp map_callback(trace_path, model, :projection = phase, argument, step) do
    validate_map_callback(trace_path, model, phase, callback(model, :project, [argument]), step)
  end

  defp validate_map_callback(_trace_path, _model, _phase, {:ok, returned}, _step) when is_map(returned),
    do: {:ok, returned}

  defp validate_map_callback(trace_path, model, phase, {:ok, returned}, step) do
    {:error, failure(trace_path, model, phase, {:invalid_return, returned}, step)}
  end

  defp validate_map_callback(trace_path, model, phase, {:raised, exception}, step) do
    {:error, failure(trace_path, model, phase, {:raised, exception}, step)}
  end

  defp callback(model, name, arguments) do
    {:ok, apply(model, name, arguments)}
  rescue
    exception -> {:raised, exception}
  end

  defp cleanup(model, implementation) do
    if function_exported?(model, :cleanup, 1) do
      cleanup_callback(model, implementation)
    else
      :ok
    end
  end

  defp cleanup_callback(model, implementation) do
    case callback(model, :cleanup, [implementation]) do
      {:ok, :ok} -> :ok
      {:ok, {:error, reason}} -> {:error, reason}
      {:ok, returned} -> {:error, {:invalid_return, returned}}
      {:raised, exception} -> {:error, {:raised, exception}}
    end
  end

  defp finish({:ok, _implementation, executed_count}, :ok, trace_path, model) do
    {:ok,
     %Report{
       trace_path: trace_path,
       model: model,
       step_count: executed_count + 1,
       executed_count: executed_count
     }}
  end

  defp finish({:ok, _implementation, _executed_count}, {:error, reason}, trace_path, model) do
    {:error, failure(trace_path, model, :cleanup, reason)}
  end

  defp finish({:error, replay_failure, _implementation}, :ok, _trace_path, _model) do
    {:error, replay_failure}
  end

  defp finish({:error, replay_failure, _implementation}, {:error, cleanup_error}, _trace_path, _model) do
    {:error, %{replay_failure | cleanup_error: cleanup_error}}
  end

  defp cleanup_implementation({:ok, implementation, _count}), do: implementation
  defp cleanup_implementation({:error, _failure, implementation}), do: implementation

  defp trace_failure(trace_path, model, error) do
    %Failure{
      trace_path: trace_path,
      model: model,
      phase: :trace_loading,
      reason: error,
      step_index: error.state_index,
      action: error.action
    }
  end

  defp failure(trace_path, model, phase, reason, step \\ nil, expected \\ nil, observed \\ nil) do
    %Failure{
      trace_path: trace_path,
      model: model,
      phase: phase,
      reason: reason,
      step_index: step && step.index,
      action: step && step.action,
      expected: expected,
      observed: observed
    }
  end
end
