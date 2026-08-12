defmodule Victoria.Workflow do
  @moduledoc """
  Runs Apalache and verifies every materialized trace against one model.

  Traces are verified sequentially in materialization order with a fresh model
  lifecycle for each trace. Verification stops at the first failure. The call
  is synchronous, has no Victoria timeout, and retains Apalache artifacts.
  """

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
  @doc "Runs a generated conformance workflow from a validated spec and plan options."
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

  defp validate_spec!(%Apalachex.Spec{}), do: :ok
  defp validate_spec!(_spec), do: raise(ArgumentError, "expected the second argument to be an Apalachex.Spec")

  defp allocate_and_run(model, spec, plan_options, apalache_options, artifact_options, generated_at, attempts_left) do
    case revalidate_spec(spec) do
      {:ok, current_spec} ->
        run_directory =
          Apalachex.RunDirectory.build(
            current_spec,
            generated_at: generated_at,
            suffix: Runtime.suffix(),
            root: Keyword.get(artifact_options, :root, "tmp/victoria")
          )

        plan = Apalachex.Plan.new(current_spec, Keyword.put(plan_options, :run_directory, run_directory))

        case Apalachex.run(plan, apalache_options) do
          {:ok, apalache_result} ->
            load_and_verify_traces(model, spec, apalache_result)

          {:error, %Apalachex.Error{} = error} ->
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

      {:error, %Apalachex.Spec.Error{} = error} ->
        workflow_error(:apalache, error, model, spec)
    end
  end

  defp revalidate_spec(%Apalachex.Spec{} = spec) do
    options = if spec.config, do: [source: spec.source, config: spec.config], else: [source: spec.source]
    Apalachex.Spec.new(options)
  end

  defp handle_apalache_error(
         %Apalachex.Error{phase: :run_directory, reason: :run_directory_already_exists} = error,
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

  defp handle_apalache_error(%Apalachex.Error{} = error, model, spec, _plan, _apalache, _artifacts, _at, _left) do
    phase = if error.phase == :run_directory, do: :run_directory, else: :apalache
    workflow_error(phase, error, model, spec)
  end

  defp load_and_verify_traces(model, spec, apalache_result) do
    case load_traces(apalache_result.itf_paths) do
      {:ok, traces} -> verify_traces(model, spec, apalache_result, traces)
      {:error, index, path, reason} -> trace_loading_error(model, spec, apalache_result, index, path, reason)
    end
  end

  defp load_traces(paths) do
    paths
    |> Enum.with_index()
    |> Enum.reduce_while({:ok, []}, fn {path, index}, {:ok, traces} ->
      case Victoria.Trace.load(path) do
        {:ok, trace} -> {:cont, {:ok, [trace | traces]}}
        {:error, error} -> {:halt, {:error, index, path, error}}
      end
    end)
    |> case do
      {:ok, traces} -> {:ok, Enum.reverse(traces)}
      error -> error
    end
  end

  defp verify_traces(model, spec, apalache_result, traces) do
    apalache_result.itf_paths
    |> Enum.zip(traces)
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

  defp trace_loading_error(model, spec, apalache_result, index, path, reason) do
    {:error,
     %Error{
       phase: :apalache,
       reason: reason,
       model: model,
       spec: spec,
       apalache: apalache_result,
       trace_index: index,
       trace_path: path,
       completed_verifications: []
     }}
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
