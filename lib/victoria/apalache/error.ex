defmodule Victoria.Apalache.Error do
  @moduledoc """
  A structured Victoria ITF trace-loading failure.

  Errors are constructed by Victoria and should be treated as read-only. Raw
  output is retained in the struct; `Exception.message/1` renders only a
  bounded, binary-safe tail.
  """

  alias Victoria.Apalache.Output
  alias Victoria.Apalache.Plan

  defexception [
    :phase,
    :reason,
    :plan,
    :executable,
    :version,
    :exit_status,
    :output,
    trace_paths: [],
    manifest_failure: nil
  ]

  @typedoc "The retained compatibility phase that failed. New Victoria errors use `:trace_loading`."
  @type phase ::
          :executable_discovery
          | :version_probe
          | :version_compatibility
          | :run_directory
          | :execution
          | :trace_discovery
          | :trace_loading
          | :manifest

  @typedoc "An Apalache failure with plan, process, artifact, and manifest context."
  @type t :: %__MODULE__{
          phase: phase(),
          reason: term(),
          plan: Plan.t(),
          executable: Path.t() | nil,
          version: Version.t() | nil,
          exit_status: non_neg_integer() | nil,
          output: binary() | nil,
          trace_paths: [Path.t()],
          manifest_failure: term() | nil
        }

  @impl Exception
  def message(%__MODULE__{} = error) do
    context = [
      "Victoria Apalache #{error.phase} error: #{render_term(error.reason)}",
      plan_context(error.plan),
      optional("executable", error.executable),
      optional("version", error.version),
      run_directory_context(error.plan),
      optional("exit status", error.exit_status),
      trace_context(error.trace_paths),
      output_context(error.output),
      manifest_failure_context(error.manifest_failure)
    ]

    context
    |> Enum.reject(&is_nil/1)
    |> Enum.join("\n")
  end

  defp plan_context(%Plan{mode: mode, spec: spec}) do
    "mode: #{mode}; source: #{inspect(spec.source)}"
  end

  defp plan_context(_plan), do: nil

  defp run_directory_context(%Plan{run_directory: run_directory}) do
    "run directory: #{inspect(run_directory)}"
  end

  defp run_directory_context(_plan), do: nil

  defp optional(_label, nil), do: nil
  defp optional(label, value), do: "#{label}: #{value}"

  defp trace_context([]), do: nil
  defp trace_context(paths), do: "trace paths: #{inspect(paths)}"

  defp output_context(nil), do: nil
  defp output_context(""), do: nil

  defp output_context(output) do
    {tail, _truncated?} = Output.tail(output)
    "output tail:\n#{tail}"
  end

  defp manifest_failure_context(nil), do: nil
  defp manifest_failure_context(reason), do: "secondary manifest failure: #{render_term(reason)}"

  defp render_term(term), do: term |> inspect() |> Output.tail() |> elem(0)
end
