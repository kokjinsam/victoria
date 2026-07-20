defmodule Victoria.Workflow do
  @moduledoc "Runs Apalache and verifies every materialized trace against one model."

  alias Victoria.Apalache
  alias Victoria.Apalache.Plan
  alias Victoria.Apalache.RunDirectory
  alias Victoria.Model
  alias Victoria.Spec
  alias Victoria.Workflow.Error
  alias Victoria.Workflow.Result
  alias Victoria.Workflow.Runtime
  alias Victoria.Workflow.Verification

  @run_directory_attempts 8
  @top_level_options [:plan, :apalache, :artifacts]
  @plan_options [:mode, :length, :max_run]
  @apalache_options [:executable]
  @artifact_options [:root]

  @spec run(module(), Spec.t(), keyword()) :: {:ok, Result.t()} | {:error, Error.t()}
  def run(model, spec, options) do
    {plan_options, apalache_options, artifact_options} = validate_options!(options)
    validate_model!(model)
    validate_spec!(spec)

    generated_at = Runtime.generated_at()

    allocate_and_run(
      model,
      spec,
      plan_options,
      apalache_options,
      artifact_options,
      generated_at,
      @run_directory_attempts
    )
  end

  defp validate_options!(options) do
    validate_group!("options", options, @top_level_options)

    if !Keyword.has_key?(options, :plan) do
      raise ArgumentError, "missing required option :plan"
    end

    plan = Keyword.fetch!(options, :plan)
    apalache = Keyword.get(options, :apalache, [])
    artifacts = Keyword.get(options, :artifacts, [])

    validate_group!(":plan", plan, @plan_options)
    validate_group!(":apalache", apalache, @apalache_options)
    validate_group!(":artifacts", artifacts, @artifact_options)

    {plan, apalache, artifacts}
  end

  defp validate_group!(label, options, allowed) do
    if !Keyword.keyword?(options) do
      raise ArgumentError, "expected #{label} to be a keyword list"
    end

    keys = Keyword.keys(options)

    if length(keys) != length(Enum.uniq(keys)) do
      raise ArgumentError, "expected #{label} to contain no duplicate keys"
    end

    case keys -- allowed do
      [] -> :ok
      unknown -> raise ArgumentError, "unknown #{label} options: #{inspect(unknown)}"
    end
  end

  defp validate_model!(model) when is_atom(model) do
    case Code.ensure_loaded(model) do
      {:module, ^model} -> validate_callbacks!(model)
      {:error, _reason} -> raise ArgumentError, "expected the first argument to name a loadable module"
    end
  end

  defp validate_model!(_model) do
    raise ArgumentError, "expected the first argument to name a loadable module"
  end

  defp validate_callbacks!(model) do
    optional = Model.behaviour_info(:optional_callbacks)
    required = Model.behaviour_info(:callbacks) -- optional
    missing = Enum.reject(required, fn {name, arity} -> function_exported?(model, name, arity) end)

    if missing != [] do
      rendered = missing |> Enum.sort() |> Enum.map_join(", ", fn {name, arity} -> "#{name}/#{arity}" end)

      raise ArgumentError,
            "invalid Victoria model #{inspect(model)}; missing required callbacks: #{rendered}"
    end
  end

  defp validate_spec!(%Spec{}), do: :ok
  defp validate_spec!(_spec), do: raise(ArgumentError, "expected the second argument to be a Victoria.Spec")

  defp allocate_and_run(model, spec, plan_options, apalache_options, artifact_options, generated_at, attempts_left) do
    run_directory =
      RunDirectory.build(
        spec,
        Keyword.merge(artifact_options, generated_at: generated_at, suffix: Runtime.suffix())
      )

    plan = Plan.new(spec, Keyword.put(plan_options, :run_directory, run_directory))

    case Apalache.run(plan, apalache_options) do
      {:ok, apalache_result} ->
        verify_traces(model, spec, apalache_result)

      {:error, %Apalache.Error{} = error} ->
        handle_apalache_error(
          error,
          model,
          spec,
          plan_options,
          apalache_options,
          artifact_options,
          generated_at,
          attempts_left
        )
    end
  end

  defp handle_apalache_error(
         %Apalache.Error{phase: :run_directory, reason: :run_directory_already_exists} = error,
         model,
         spec,
         plan_options,
         apalache_options,
         artifact_options,
         generated_at,
         attempts_left
       ) do
    if attempts_left > 1 do
      allocate_and_run(
        model,
        spec,
        plan_options,
        apalache_options,
        artifact_options,
        generated_at,
        attempts_left - 1
      )
    else
      workflow_error(
        :run_directory,
        {:run_directory_allocation_exhausted, @run_directory_attempts, error},
        model,
        spec
      )
    end
  end

  defp handle_apalache_error(%Apalache.Error{} = error, model, spec, _plan, _apalache, _artifacts, _at, _left) do
    phase = if error.phase == :run_directory, do: :run_directory, else: :apalache
    workflow_error(phase, error, model, spec)
  end

  defp verify_traces(model, spec, apalache_result) do
    apalache_result.trace_paths
    |> Enum.zip(apalache_result.traces)
    |> Enum.with_index()
    |> Enum.reduce_while([], fn {{trace_path, trace}, trace_index}, completed ->
      case Victoria.verify(model, trace: trace) do
        {:ok, report} ->
          verification = %Verification{trace_index: trace_index, trace_path: trace_path, report: report}
          {:cont, [verification | completed]}

        {:error, reason} ->
          error = %Error{
            phase: :verification,
            reason: reason,
            model: model,
            spec: spec,
            apalache: apalache_result,
            trace_index: trace_index,
            trace_path: trace_path,
            completed_verifications: Enum.reverse(completed)
          }

          {:halt, {:error, error}}
      end
    end)
    |> case do
      {:error, %Error{} = error} -> {:error, error}
      completed -> {:ok, %Result{model: model, apalache: apalache_result, verifications: Enum.reverse(completed)}}
    end
  end

  defp workflow_error(phase, reason, model, spec) do
    {:error,
     %Error{
       phase: phase,
       reason: reason,
       model: model,
       spec: spec,
       completed_verifications: []
     }}
  end
end
