defmodule Victoria.Runner.Failure do
  @moduledoc "Structured failure returned by fixed-trace replay."

  @enforce_keys [:trace_path, :model, :phase, :reason]
  defexception [
    :trace_path,
    :model,
    :phase,
    :reason,
    :step_index,
    :action,
    :expected,
    :observed,
    :cleanup_error
  ]

  @type phase ::
          :trace_validation
          | :initialization
          | :initial_verification
          | :execution
          | :snapshot
          | :projection
          | :step_verification
          | :cleanup

  @type t :: %__MODULE__{
          trace_path: Path.t(),
          model: module(),
          phase: phase(),
          reason: term(),
          step_index: non_neg_integer() | nil,
          action: String.t() | nil,
          expected: map() | nil,
          observed: map() | nil,
          cleanup_error: term() | nil
        }

  @impl Exception
  def message(failure) do
    [
      "Victoria verification failure",
      field("Model", inspect(failure.model)),
      field("Phase", format_phase(failure.phase)),
      optional_field("Step", failure.step_index),
      optional_field("Action", failure.action),
      comparison_fields(failure),
      field("Reason", format_reason(failure.reason)),
      optional_field("Cleanup error", failure.cleanup_error, &inspect/1),
      field("Trace", failure.trace_path)
    ]
    |> List.flatten()
    |> Enum.reject(&is_nil/1)
    |> Enum.join("\n\n")
  end

  defp comparison_fields(%{phase: phase} = failure) when phase in [:initial_verification, :step_verification] do
    [field("Expected", inspect(failure.expected)), field("Observed", inspect(failure.observed))]
  end

  defp comparison_fields(_failure), do: nil

  defp optional_field(_label, nil, _formatter), do: nil
  defp optional_field(label, value, formatter), do: field(label, formatter.(value))
  defp optional_field(label, value), do: optional_field(label, value, &to_string/1)

  defp field(label, value), do: "#{label}:\n  #{value}"

  defp format_reason(:states_differ), do: "states differ"
  defp format_reason(reason), do: inspect(reason)

  defp format_phase(phase) do
    phase
    |> Atom.to_string()
    |> String.replace("_", " ")
  end
end
