defmodule Victoria.Apalache do
  @moduledoc """
  Runs a Victoria plan through Apalachex and loads its retained ITF artifacts.

  Apalachex owns executable discovery, version validation, process execution,
  run-directory reservation, artifact discovery, and the execution manifest.
  Victoria owns ITF decoding and returns its existing result structure.
  """

  alias Victoria.Apalache.Error
  alias Victoria.Apalache.Plan
  alias Victoria.Apalache.Result
  alias Victoria.Spec
  alias Victoria.Trace

  @spec run(Plan.t(), keyword()) ::
          {:ok, Result.t()} | {:error, Apalachex.Error.t() | Apalachex.Spec.Error.t() | Error.t()}
  @doc """
  Executes `plan` through Apalachex 0.1.x and loads every returned ITF path.

  The only option is `:executable`. Apalachex errors are returned intact.
  Invalid arguments raise `ArgumentError`.
  """
  def run(plan, options \\ [])

  def run(%Plan{} = plan, options) do
    with {:ok, spec} <- apalachex_spec(plan.spec),
         apalachex_plan = Apalachex.Plan.new(spec, apalachex_plan_options(plan)),
         {:ok, execution} <- Apalachex.run(apalachex_plan, options),
         {:ok, traces} <- load_traces(plan, execution) do
      {:ok,
       %Result{
         plan: plan,
         executable: execution.executable,
         version: execution.version,
         exit_status: execution.exit_status,
         output: execution.output,
         trace_paths: execution.itf_paths,
         traces: traces
       }}
    end
  end

  def run(_plan, _options) do
    raise ArgumentError, "expected the first argument to be a Victoria.Apalache.Plan"
  end

  defp apalachex_spec(%Spec{} = spec) do
    options = if spec.config, do: [source: spec.source, config: spec.config], else: [source: spec.source]
    Apalachex.Spec.new(options)
  end

  defp apalachex_plan_options(%Plan{} = plan) do
    maybe_put_max_run([mode: plan.mode, length: plan.options.length, run_directory: plan.run_directory], plan.options)
  end

  defp maybe_put_max_run(options, %{max_run: max_run}), do: Keyword.put(options, :max_run, max_run)
  defp maybe_put_max_run(options, _plan_options), do: options

  defp load_traces(plan, execution) do
    execution.itf_paths
    |> Enum.reduce_while({:ok, []}, fn path, {:ok, traces} ->
      case Trace.load(path) do
        {:ok, trace} -> {:cont, {:ok, [trace | traces]}}
        {:error, error} -> {:halt, trace_loading_error(plan, execution, path, error)}
      end
    end)
    |> case do
      {:ok, traces} -> {:ok, Enum.reverse(traces)}
      {:error, %Error{} = error} -> {:error, error}
    end
  end

  defp trace_loading_error(plan, execution, path, error) do
    {:error,
     %Error{
       plan: plan,
       phase: :trace_loading,
       reason: {:invalid_trace, path, error},
       executable: execution.executable,
       version: execution.version,
       exit_status: execution.exit_status,
       output: execution.output,
       trace_paths: execution.itf_paths
     }}
  end
end
