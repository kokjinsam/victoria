defmodule Victoria.Workflow.Verification do
  @moduledoc """
  Associates one generated trace with its successful verification report.

  Values are constructed by Victoria and should be treated as read-only.
  """

  alias Victoria.Runner

  @enforce_keys [:trace_index, :trace_path, :report]
  defstruct [:trace_index, :trace_path, :report]

  @typedoc "One positionally indexed successful generated-trace verification."
  @type t :: %__MODULE__{
          trace_index: non_neg_integer(),
          trace_path: Path.t(),
          report: Runner.Report.t()
        }
end
