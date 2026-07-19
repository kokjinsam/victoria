defmodule Victoria.Apalache.Error do
  @moduledoc "A structured Apalache execution or trace-materialization failure."

  alias Victoria.Apalache.Plan

  @output_tail_bytes 4096

  defexception [
    :phase,
    :reason,
    :plan,
    :executable,
    :version,
    :exit_status,
    :output,
    trace_paths: []
  ]

  @type phase ::
          :executable_discovery
          | :version_probe
          | :version_compatibility
          | :run_directory
          | :execution
          | :trace_discovery
          | :trace_loading

  @type t :: %__MODULE__{
          phase: phase(),
          reason: term(),
          plan: Plan.t(),
          executable: Path.t() | nil,
          version: Version.t() | nil,
          exit_status: non_neg_integer() | nil,
          output: binary() | nil,
          trace_paths: [Path.t()]
        }

  @impl Exception
  def message(%__MODULE__{} = error) do
    context = [
      "Victoria Apalache #{error.phase} error: #{inspect(error.reason)}",
      plan_context(error.plan),
      optional("executable", error.executable),
      optional("version", error.version),
      run_directory_context(error.plan),
      optional("exit status", error.exit_status),
      trace_context(error.trace_paths),
      output_context(error.output)
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
    tail = safe_binary_tail(output, @output_tail_bytes)
    "output tail:\n#{tail}"
  end

  defp safe_binary_tail(binary, maximum) do
    tail = binary_tail(binary, maximum)

    cond do
      String.valid?(tail) -> tail
      String.valid?(binary) -> trim_to_codepoint_boundary(tail)
      true -> inspect(tail, binaries: :as_binaries)
    end
  end

  defp binary_tail(binary, maximum) when byte_size(binary) <= maximum, do: binary

  defp binary_tail(binary, maximum) do
    start = byte_size(binary) - maximum
    binary_part(binary, start, maximum)
  end

  defp trim_to_codepoint_boundary(<<_byte, rest::binary>>) do
    if String.valid?(rest), do: rest, else: trim_to_codepoint_boundary(rest)
  end
end
