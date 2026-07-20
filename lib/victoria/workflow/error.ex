defmodule Victoria.Workflow.Error do
  @moduledoc """
  A contextual conformance-workflow failure.

  Errors are constructed by Victoria and should be treated as read-only.
  Verification failures retain earlier successful verifications and the full
  Apalache result.
  """

  alias Victoria.Apalache
  alias Victoria.Apalache.Output
  alias Victoria.Spec
  alias Victoria.Workflow.Verification

  defexception [
    :phase,
    :reason,
    :model,
    :spec,
    :apalache,
    :trace_index,
    :trace_path,
    completed_verifications: []
  ]

  @typedoc "The workflow phase that failed."
  @type phase :: :run_directory | :apalache | :verification
  @typedoc "A run-directory, Apalache, or implementation-verification failure."
  @type t :: %__MODULE__{
          phase: phase(),
          reason: term(),
          model: module(),
          spec: Spec.t(),
          apalache: Apalache.Result.t() | nil,
          trace_index: non_neg_integer() | nil,
          trace_path: Path.t() | nil,
          completed_verifications: [Verification.t()]
        }

  @impl Exception
  def message(%__MODULE__{reason: {:run_directory_allocation_exhausted, attempts, last_error}} = error) do
    Enum.join(
      [
        "Victoria workflow could not allocate a unique run directory",
        field("Attempts", attempts),
        field("Specification", error.spec.source),
        field("Last cause", render_reason(last_error))
      ],
      "\n\n"
    )
  end

  def message(%__MODULE__{phase: :verification} = error) do
    Enum.join(
      [
        "Victoria workflow verification failed",
        field("Model", inspect(error.model)),
        field("Specification", error.spec.source),
        field("Trace index", error.trace_index),
        field("Trace", error.trace_path),
        field("Previously verified traces", length(error.completed_verifications)),
        field("Cause", render_reason(error.reason))
      ],
      "\n\n"
    )
  end

  def message(%__MODULE__{} = error) do
    Enum.join(
      [
        "Victoria workflow failed during Apalache execution",
        field("Model", inspect(error.model)),
        field("Specification", error.spec.source),
        field("Cause", render_reason(error.reason))
      ],
      "\n\n"
    )
  end

  defp field(label, value), do: "#{label}:\n  #{value}"

  defp render_reason(%{__exception__: true} = exception) do
    exception
    |> Exception.message()
    |> Output.tail()
    |> elem(0)
  end

  defp render_reason(reason) do
    reason
    |> inspect()
    |> Output.tail()
    |> elem(0)
  end
end
