defmodule Victoria.Runner.Report do
  @moduledoc """
  Summary returned after a successful fixed-trace replay.

  Reports are constructed by Victoria and should be treated as read-only.
  """

  @enforce_keys [:trace_path, :model, :step_count, :executed_count]
  defstruct [:trace_path, :model, :step_count, :executed_count]

  @typedoc "Successful replay counts and provenance."
  @type t :: %__MODULE__{
          trace_path: Path.t(),
          model: module(),
          step_count: pos_integer(),
          executed_count: non_neg_integer()
        }
end
